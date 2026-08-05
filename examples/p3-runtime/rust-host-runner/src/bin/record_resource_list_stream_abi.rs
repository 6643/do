use anyhow::{Context, Result, bail};
use std::collections::VecDeque;
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

const CANONICAL_SOURCE_INSTANCE: &str = "do:record-resource-list-stream-canonical/source@0.1.0";
const CANONICAL_PROBE_INSTANCE: &str = "do:record-resource-list-stream-canonical/probe@0.1.0";
const GENERATED_SOURCE_INSTANCE: &str = "do:record-resource-list-stream-probe/source@0.1.0";
const GENERATED_PROBE_INSTANCE: &str = "do:record-resource-list-stream-probe/probe@0.1.0";

const LIST_RESULT_POINTER: u32 = 64;
const LIST_RESULT_LENGTH: u32 = 68;
const LIST_ELEMENT_STRIDE: u32 = 4;
const LIST_TICKET_OFFSET: u32 = 0;

pub struct Ticket {
    _value: u32,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct ResourceEntry {
    ticket: Resource<Ticket>,
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
#[allow(dead_code)]
enum ErrorCode {
    #[component(name = "io")]
    Io,
}

#[derive(Default)]
struct Stats {
    entries: Vec<u32>,
    stream_read_calls: u32,
    completion_polls: u32,
    stream_drops: u32,
    future_drops: u32,
    resource_created: u32,
    resource_drops: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Mode {
    ReadyEmpty,
    ReadyOne,
    ReadyThree,
    RepeatReadyThree,
    Pending,
    CompletionError,
    EarlyDrop,
    MalformedLen,
    DuplicateDrop,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "ready-empty" => Ok(Self::ReadyEmpty),
            "ready-one" => Ok(Self::ReadyOne),
            "ready-three" => Ok(Self::ReadyThree),
            "repeat-ready-three" => Ok(Self::RepeatReadyThree),
            "pending" => Ok(Self::Pending),
            "completion-error" => Ok(Self::CompletionError),
            "early-drop" => Ok(Self::EarlyDrop),
            "malformed-len" => Ok(Self::MalformedLen),
            "duplicate-drop" => Ok(Self::DuplicateDrop),
            other => bail!(
                "mode must be ready-empty, ready-one, ready-three, repeat-ready-three, pending, completion-error, early-drop, malformed-len, or duplicate-drop (got {other})"
            ),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::ReadyEmpty => "ready-empty",
            Self::ReadyOne => "ready-one",
            Self::ReadyThree => "ready-three",
            Self::RepeatReadyThree => "repeat-ready-three",
            Self::Pending => "pending",
            Self::CompletionError => "completion-error",
            Self::EarlyDrop => "early-drop",
            Self::MalformedLen => "malformed-len",
            Self::DuplicateDrop => "duplicate-drop",
        }
    }

    fn values(self) -> Vec<u32> {
        match self {
            Self::ReadyEmpty => Vec::new(),
            Self::ReadyOne => vec![111],
            Self::ReadyThree | Self::RepeatReadyThree => vec![111, 222, 333],
            Self::Pending
            | Self::CompletionError
            | Self::EarlyDrop
            | Self::MalformedLen
            | Self::DuplicateDrop => vec![111, 222, 333],
        }
    }

    fn is_trap(self) -> bool {
        matches!(self, Self::MalformedLen | Self::DuplicateDrop)
    }

    fn call_count(self) -> u32 {
        if self == Self::RepeatReadyThree {
            6000
        } else {
            1
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CompletionMode {
    Ready,
    Pending,
    Error,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Package {
    Canonical,
    Generated,
}

impl Package {
    fn source_instance(self) -> &'static str {
        match self {
            Self::Canonical => CANONICAL_SOURCE_INSTANCE,
            Self::Generated => GENERATED_SOURCE_INSTANCE,
        }
    }

    fn probe_instance(self) -> &'static str {
        match self {
            Self::Canonical => CANONICAL_PROBE_INSTANCE,
            Self::Generated => GENERATED_PROBE_INSTANCE,
        }
    }
}

struct State {
    table: ResourceTable,
    stats: Arc<Mutex<Stats>>,
}

struct ListStream {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<Vec<u32>>,
}

impl StreamProducer<State> for ListStream {
    type Item = Vec<ResourceEntry>;
    type Buffer = VecBuffer<Vec<ResourceEntry>>;

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
        stream
            .stats
            .lock()
            .expect("list stream stats mutex poisoned")
            .stream_read_calls += 1;
        let Some(values) = stream.entries.pop_front() else {
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        let mut records = Vec::with_capacity(values.len());
        for value in values {
            let ticket = store.data_mut().table.push(Ticket { _value: value })?;
            stream
                .stats
                .lock()
                .expect("list stream stats mutex poisoned")
                .entries
                .push(value);
            stream
                .stats
                .lock()
                .expect("list stream stats mutex poisoned")
                .resource_created += 1;
            records.push(ResourceEntry { ticket });
        }
        destination.set_buffer(vec![records].into());
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for ListStream {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("list stream stats mutex poisoned")
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
            .expect("list completion stats mutex poisoned")
            .completion_polls += 1;
        if self.mode == CompletionMode::Pending && !self.polled {
            self.polled = true;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        self.polled = true;
        if self.mode == CompletionMode::Error {
            Poll::Ready(Ok(Err(ErrorCode::Io)))
        } else {
            Poll::Ready(Ok(Ok(())))
        }
    }
}

impl Drop for Completion {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("list completion stats mutex poisoned")
            .future_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn format_entries(values: &[u32]) -> String {
    values
        .iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(",")
}

fn install_source(
    linker: &mut Linker<State>,
    package: Package,
    stats: Arc<Mutex<Stats>>,
    values: Vec<u32>,
    completion_mode: CompletionMode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(package.source_instance())?;
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state
                .stats
                .lock()
                .expect("list resource drop stats mutex poisoned")
                .resource_drops += 1;
            let resource = Resource::<Ticket>::new_own(rep);
            let _ = state.table.delete(resource)?;
            Ok(())
        },
    )?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let reader = StreamReader::new(
            &mut store,
            ListStream {
                stats: Arc::clone(&stats),
                entries: VecDeque::from([values.clone()]),
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            Completion {
                stats: Arc::clone(&stats),
                mode: completion_mode,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

async fn run(component_path: &Path, mode: Mode, package: Package) -> Result<()> {
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
    map_wasmtime(install_source(
        &mut linker,
        package,
        Arc::clone(&stats),
        mode.values(),
        if mode == Mode::Pending {
            CompletionMode::Pending
        } else if mode == Mode::CompletionError {
            CompletionMode::Error
        } else {
            CompletionMode::Ready
        },
    ))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, package.probe_instance())
        .context("missing list-resource probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing list-resource probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let call_count = mode.call_count();
    let source_values = mode.values();
    let result = if mode.is_trap() {
        let call = store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await;
        match call {
            Ok(Ok(result)) => bail!("{} unexpectedly completed: {:?}", mode.name(), result.0),
            Ok(Err(_)) | Err(_) => None,
        }
    } else {
        let expected_result = if mode == Mode::CompletionError {
            Err(ErrorCode::Io)
        } else {
            Ok(())
        };
        for _ in 0..call_count {
            let call = store
                .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
                .await;
            let call_result = map_wasmtime(map_wasmtime(call)?)?;
            if call_result.0 != expected_result {
                bail!("unexpected component result: {:?}", call_result.0);
            }
        }
        Some(expected_result)
    };
    let snapshot = stats.lock().expect("list resource stats mutex poisoned");
    let mut expected = Vec::with_capacity(source_values.len() * call_count as usize);
    for _ in 0..call_count {
        expected.extend_from_slice(&source_values);
    }
    let expected_polls = if mode == Mode::Pending {
        2
    } else if mode == Mode::EarlyDrop || mode.is_trap() {
        0
    } else {
        call_count
    };
    let expected_drops = if mode == Mode::MalformedLen {
        0
    } else {
        expected.len() as u32
    };
    let expected_handle_drops = if mode.is_trap() { 0 } else { call_count };
    let table_empty = store.data().table.is_empty();
    if snapshot.entries != expected
        || snapshot.stream_read_calls != call_count
        || snapshot.completion_polls != expected_polls
        || snapshot.stream_drops != expected_handle_drops
        || snapshot.future_drops != expected_handle_drops
        || snapshot.resource_created != expected.len() as u32
        || snapshot.resource_drops != expected_drops
        || table_empty != (mode != Mode::MalformedLen)
    {
        bail!(
            "unexpected list resource stats: mode={} entries={:?} stream-reads={} completion-polls={} stream-drops={} future-drops={} resource-created={} resource-drops={} table-empty={}",
            mode.name(),
            snapshot.entries,
            snapshot.stream_read_calls,
            snapshot.completion_polls,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            table_empty,
        );
    }
    println!(
        "mode={} entries=[{}] resource-created={} resource-drops={} stream-drops={} future-drops={} completion-polls={} table-empty={} observed-list-pointer={} observed-list-length-offset={} observed-list-length={} observed-list-element-stride={} observed-list-ticket-offset={} result={} trap={} stream-reads={}",
        mode.name(),
        format_entries(&snapshot.entries),
        snapshot.resource_created,
        snapshot.resource_drops,
        snapshot.stream_drops,
        snapshot.future_drops,
        snapshot.completion_polls,
        table_empty,
        LIST_RESULT_POINTER,
        LIST_RESULT_LENGTH,
        source_values.len(),
        LIST_ELEMENT_STRIDE,
        LIST_TICKET_OFFSET,
        match result {
            Some(Ok(())) => "Ok",
            Some(Err(ErrorCode::Io)) => "Err(io)",
            None => "none",
        },
        mode.is_trap(),
        snapshot.stream_read_calls,
    );
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: do-p3-record-resource-list-abi <component.wasm> [--generated] <mode>")?;
    let first = args
        .next()
        .context("usage: do-p3-record-resource-list-abi <component.wasm> [--generated] <mode>")?;
    let (package, mode_name) = if first == "--generated" {
        (
            Package::Generated,
            args.next().context(
                "usage: do-p3-record-resource-list-abi <component.wasm> [--generated] <mode>",
            )?,
        )
    } else {
        (Package::Canonical, first)
    };
    if args.next().is_some() {
        bail!("usage: do-p3-record-resource-list-abi <component.wasm> [--generated] <mode>");
    }
    futures::executor::block_on(run(
        Path::new(&component_path),
        Mode::parse(&mode_name)?,
        package,
    ))
}
