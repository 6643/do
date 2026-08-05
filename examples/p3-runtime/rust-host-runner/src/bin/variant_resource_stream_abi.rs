use anyhow::{Context, Result, bail};
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Destination, FutureReader, Linker, Resource, ResourceTable, ResourceType,
    StreamProducer, StreamReader, StreamResult, VecBuffer,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const SOURCE_INSTANCE: &str = "do:variant-resource-stream-canonical/source@0.1.0";
const PROBE_INSTANCE: &str = "do:variant-resource-stream-canonical/probe@0.1.0";

const EVENT_RESULT_POINTER: u32 = 64;
const EVENT_TAG_OFFSET: u32 = 0;
const EVENT_PAYLOAD_OFFSET: u32 = 4;
const EVENT_SIZE: u32 = 8;
const EVENT_ALIGNMENT: u32 = 4;

pub struct Ticket {
    _value: u32,
}

#[derive(
    Clone,
    Copy,
    Debug,
    PartialEq,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(enum)]
#[repr(u8)]
enum ErrorCode {
    #[component(name = "io")]
    Io,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(variant)]
enum Event {
    #[component(name = "ticket")]
    Ticket(Resource<Ticket>),
    #[component(name = "idle")]
    Idle,
    #[component(name = "failed")]
    Failed(ErrorCode),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ObservedEvent {
    Ticket,
    Idle,
    FailedIo,
}

impl ObservedEvent {
    fn name(self) -> &'static str {
        match self {
            Self::Ticket => "ticket",
            Self::Idle => "idle",
            Self::FailedIo => "failed(io)",
        }
    }
}

#[derive(Default)]
struct Stats {
    event: Option<ObservedEvent>,
    stream_read_calls: u32,
    completion_polls: u32,
    stream_drops: u32,
    future_drops: u32,
    resource_created: u32,
    resource_drops: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Mode {
    TicketReady,
    IdleReady,
    FailedReady,
    TicketPending,
    CompletionError,
    EarlyDrop,
    MalformedTag,
    DuplicateRelease,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "ticket-ready" => Ok(Self::TicketReady),
            "idle-ready" => Ok(Self::IdleReady),
            "failed-ready" => Ok(Self::FailedReady),
            "ticket-pending" => Ok(Self::TicketPending),
            "completion-error" => Ok(Self::CompletionError),
            "early-drop" => Ok(Self::EarlyDrop),
            "malformed-tag" => Ok(Self::MalformedTag),
            "duplicate-release" => Ok(Self::DuplicateRelease),
            other => bail!(
                "mode must be ticket-ready, idle-ready, failed-ready, ticket-pending, completion-error, early-drop, malformed-tag, or duplicate-release (got {other})"
            ),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::TicketReady => "ticket-ready",
            Self::IdleReady => "idle-ready",
            Self::FailedReady => "failed-ready",
            Self::TicketPending => "ticket-pending",
            Self::CompletionError => "completion-error",
            Self::EarlyDrop => "early-drop",
            Self::MalformedTag => "malformed-tag",
            Self::DuplicateRelease => "duplicate-release",
        }
    }

    fn event(self) -> ObservedEvent {
        match self {
            Self::TicketReady
            | Self::TicketPending
            | Self::CompletionError
            | Self::EarlyDrop
            | Self::MalformedTag
            | Self::DuplicateRelease => ObservedEvent::Ticket,
            Self::IdleReady => ObservedEvent::Idle,
            Self::FailedReady => ObservedEvent::FailedIo,
        }
    }

    fn completion_mode(self) -> CompletionMode {
        match self {
            Self::TicketPending => CompletionMode::Pending,
            Self::CompletionError => CompletionMode::Error,
            Self::TicketReady
            | Self::IdleReady
            | Self::FailedReady
            | Self::EarlyDrop
            | Self::MalformedTag
            | Self::DuplicateRelease => CompletionMode::Ready,
        }
    }

    fn expected_result(self) -> std::result::Result<(), ErrorCode> {
        match self {
            Self::FailedReady | Self::CompletionError => Err(ErrorCode::Io),
            Self::TicketReady | Self::IdleReady | Self::TicketPending | Self::EarlyDrop => Ok(()),
            Self::MalformedTag | Self::DuplicateRelease => unreachable!(),
        }
    }

    fn expected_completion_polls(self) -> u32 {
        match self {
            Self::FailedReady | Self::EarlyDrop => 0,
            Self::TicketPending => 2,
            Self::TicketReady | Self::IdleReady | Self::CompletionError => 1,
            Self::MalformedTag | Self::DuplicateRelease => unreachable!(),
        }
    }

    fn expected_resource_count(self) -> u32 {
        match self.event() {
            ObservedEvent::Ticket => 1,
            ObservedEvent::Idle | ObservedEvent::FailedIo => 0,
        }
    }

    fn expected_resource_drops(self) -> u32 {
        if self == Self::MalformedTag {
            0
        } else {
            self.expected_resource_count()
        }
    }

    fn expects_empty_table(self) -> bool {
        self != Self::MalformedTag
    }

    fn is_trap(self) -> bool {
        matches!(self, Self::MalformedTag | Self::DuplicateRelease)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CompletionMode {
    Ready,
    Pending,
    Error,
}

struct State {
    table: ResourceTable,
    stats: Arc<Mutex<Stats>>,
}

struct EventStream {
    stats: Arc<Mutex<Stats>>,
    event: ObservedEvent,
    emitted: bool,
}

impl StreamProducer<State> for EventStream {
    type Item = Event;
    type Buffer = VecBuffer<Event>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }

        let stream = self.get_mut();
        if stream.emitted {
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        }
        stream.emitted = true;
        stream
            .stats
            .lock()
            .expect("variant stream stats mutex poisoned")
            .stream_read_calls += 1;
        stream
            .stats
            .lock()
            .expect("variant stream stats mutex poisoned")
            .event = Some(stream.event);

        let event = match stream.event {
            ObservedEvent::Ticket => {
                let ticket = store.data_mut().table.push(Ticket { _value: 111 })?;
                stream
                    .stats
                    .lock()
                    .expect("variant stream stats mutex poisoned")
                    .resource_created += 1;
                Event::Ticket(ticket)
            }
            ObservedEvent::Idle => Event::Idle,
            ObservedEvent::FailedIo => Event::Failed(ErrorCode::Io),
        };
        destination.set_buffer(vec![event].into());
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for EventStream {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("variant stream stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct Completion {
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
    polled: bool,
}

impl Future for Completion {
    type Output = wasmtime::Result<std::result::Result<(), ErrorCode>>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        self.stats
            .lock()
            .expect("variant completion stats mutex poisoned")
            .completion_polls += 1;
        if self.mode == CompletionMode::Pending && !self.polled {
            self.polled = true;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        self.polled = true;
        match self.mode {
            CompletionMode::Error => Poll::Ready(Ok(Err(ErrorCode::Io))),
            CompletionMode::Ready | CompletionMode::Pending => Poll::Ready(Ok(Ok(()))),
        }
    }
}

impl Drop for Completion {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("variant completion stats mutex poisoned")
            .future_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn install_source(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: Mode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_INSTANCE)?;
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state
                .stats
                .lock()
                .expect("variant resource drop stats mutex poisoned")
                .resource_drops += 1;
            let resource = Resource::<Ticket>::new_own(rep);
            let _ = state.table.delete(resource)?;
            Ok(())
        },
    )?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let reader = StreamReader::new(
            &mut store,
            EventStream {
                stats: Arc::clone(&stats),
                event: mode.event(),
                emitted: false,
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            Completion {
                stats: Arc::clone(&stats),
                mode: mode.completion_mode(),
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

async fn run(component_path: &Path, mode: Mode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_source(&mut linker, Arc::clone(&stats), mode))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_INSTANCE)
        .context("missing variant-resource probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing variant-resource probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let result = if mode.is_trap() {
        let call = store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await;
        match call {
            Ok(Ok(result)) => bail!("{} unexpectedly completed: {:?}", mode.name(), result.0),
            Ok(Err(_)) | Err(_) => None,
        }
    } else {
        let call = store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await;
        let result = map_wasmtime(map_wasmtime(call)?)?.0;
        if result != mode.expected_result() {
            bail!("unexpected component result: {result:?}");
        }
        Some(result)
    };

    let snapshot = stats.lock().expect("variant resource stats mutex poisoned");
    let expected_resource_count = mode.expected_resource_count();
    let table_empty = store.data().table.is_empty();
    if snapshot.event != Some(mode.event())
        || snapshot.stream_read_calls != 1
        || snapshot.resource_created != expected_resource_count
        || snapshot.resource_drops != mode.expected_resource_drops()
        || table_empty != mode.expects_empty_table()
    {
        bail!(
            "unexpected variant resource stats: mode={} event={:?} stream-reads={} completion-polls={} stream-drops={} future-drops={} resource-created={} resource-drops={} table-empty={}",
            mode.name(),
            snapshot.event,
            snapshot.stream_read_calls,
            snapshot.completion_polls,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            table_empty,
        );
    }
    if !mode.is_trap()
        && (snapshot.completion_polls != mode.expected_completion_polls()
            || snapshot.stream_drops != 1
            || snapshot.future_drops != 1)
    {
        bail!(
            "unexpected variant endpoint stats: mode={} completion-polls={} stream-drops={} future-drops={}",
            mode.name(),
            snapshot.completion_polls,
            snapshot.stream_drops,
            snapshot.future_drops,
        );
    }
    println!(
        "mode={} event={} resource-created={} resource-drops={} stream-drops={} future-drops={} completion-polls={} table-empty={} result={} trap={} observed-event-result-pointer={} observed-event-tag-offset={} observed-event-payload-offset={} observed-event-size={} observed-event-alignment={}",
        mode.name(),
        mode.event().name(),
        snapshot.resource_created,
        snapshot.resource_drops,
        snapshot.stream_drops,
        snapshot.future_drops,
        snapshot.completion_polls,
        table_empty,
        match result {
            Some(Ok(())) => "Ok",
            Some(Err(ErrorCode::Io)) => "Err(io)",
            None => "none",
        },
        mode.is_trap(),
        EVENT_RESULT_POINTER,
        EVENT_TAG_OFFSET,
        EVENT_PAYLOAD_OFFSET,
        EVENT_SIZE,
        EVENT_ALIGNMENT,
    );
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: do-p3-variant-resource-stream-abi <component.wasm> <mode>")?;
    let mode_name = args
        .next()
        .context("usage: do-p3-variant-resource-stream-abi <component.wasm> <mode>")?;
    if args.next().is_some() {
        bail!("usage: do-p3-variant-resource-stream-abi <component.wasm> <mode>");
    }
    futures::executor::block_on(run(Path::new(&component_path), Mode::parse(&mode_name)?))
}
