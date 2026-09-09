use anyhow::{Context, Result, bail};
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Linker, Resource, ResourceTable, ResourceType, Source, StreamConsumer, StreamReader,
    StreamResult,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const TYPES_INSTANCE: &str = "do:g6-2-owned-record-mixed-producer/types@0.1.0";
const SOURCE_INSTANCE: &str = "do:g6-2-owned-record-mixed-producer/source@0.1.0";
const SINK_INSTANCE: &str = "do:g6-2-owned-record-mixed-producer/sink@0.1.0";

const RECORD_OFFSET: u32 = 64;
const RECORD_BYTE_SIZE: u32 = 8;
const RECORD_ALIGNMENT: u32 = 4;
const RECORD_CODE_OFFSET: u32 = 0;
const RECORD_TICKET_OFFSET: u32 = 4;
const STREAM_CAPACITY: u32 = 1;

pub struct Ticket {
    seed: u32,
}

#[derive(
    Clone,
    Copy,
    Debug,
    PartialEq,
    Eq,
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
    #[component(name = "pipe")]
    Pipe,
    #[component(name = "invalid-mode")]
    InvalidMode,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct MixedEntry {
    code: u32,
    ticket: Resource<Ticket>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Ready,
    Pending,
    SinkErrorBefore,
    SinkErrorAfter,
    CancelBeforeTransfer,
    CancelAfterTransfer,
    EarlyDropBeforeTransfer,
    EarlyDropAfterTransfer,
    Repeat,
    Invalid,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "ready" => Ok(Self::Ready),
            "pending" => Ok(Self::Pending),
            "sink-error-before" => Ok(Self::SinkErrorBefore),
            "sink-error-after" => Ok(Self::SinkErrorAfter),
            "cancel-before-transfer" => Ok(Self::CancelBeforeTransfer),
            "cancel-after-transfer" => Ok(Self::CancelAfterTransfer),
            "early-drop-before-transfer" => Ok(Self::EarlyDropBeforeTransfer),
            "early-drop-after-transfer" => Ok(Self::EarlyDropAfterTransfer),
            "repeat" => Ok(Self::Repeat),
            "invalid" => Ok(Self::Invalid),
            other => bail!(
                "mode must be ready, pending, sink-error-before, sink-error-after, cancel-before-transfer, cancel-after-transfer, early-drop-before-transfer, early-drop-after-transfer, repeat, or invalid (got {other})"
            ),
        }
    }

    fn input(self) -> u32 {
        match self {
            Self::Ready => 0,
            Self::Pending => 1,
            Self::SinkErrorBefore => 2,
            Self::SinkErrorAfter => 3,
            Self::CancelBeforeTransfer => 4,
            Self::CancelAfterTransfer => 5,
            Self::EarlyDropBeforeTransfer => 6,
            Self::EarlyDropAfterTransfer => 7,
            Self::Repeat => 8,
            Self::Invalid => 255,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Ready => "ready",
            Self::Pending => "pending",
            Self::SinkErrorBefore => "sink-error-before",
            Self::SinkErrorAfter => "sink-error-after",
            Self::CancelBeforeTransfer => "cancel-before-transfer",
            Self::CancelAfterTransfer => "cancel-after-transfer",
            Self::EarlyDropBeforeTransfer => "early-drop-before-transfer",
            Self::EarlyDropAfterTransfer => "early-drop-after-transfer",
            Self::Repeat => "repeat",
            Self::Invalid => "invalid",
        }
    }

    fn sink_pending(self) -> bool {
        matches!(self, Self::Pending)
    }

    fn sink_error_before(self) -> bool {
        matches!(self, Self::SinkErrorBefore)
    }

    fn sink_error_after(self) -> bool {
        matches!(self, Self::SinkErrorAfter)
    }

    fn hold_call(self) -> bool {
        matches!(
            self,
            Self::CancelBeforeTransfer
                | Self::CancelAfterTransfer
                | Self::EarlyDropBeforeTransfer
                | Self::EarlyDropAfterTransfer
        )
    }

    fn expected_result(self) -> std::result::Result<(), ErrorCode> {
        match self {
            Self::Ready | Self::Pending | Self::Repeat => Ok(()),
            Self::Invalid => Err(ErrorCode::InvalidMode),
            Self::SinkErrorAfter
            | Self::CancelBeforeTransfer
            | Self::CancelAfterTransfer
            | Self::EarlyDropBeforeTransfer
            | Self::EarlyDropAfterTransfer => Err(ErrorCode::Pipe),
            Self::SinkErrorBefore => Err(ErrorCode::Io),
        }
    }

    fn expected_received(self) -> &'static [(u32, u32)] {
        match self {
            Self::Ready => &[(7, 111)],
            Self::Pending => &[(9, 222)],
            Self::SinkErrorAfter => &[(13, 444)],
            Self::CancelAfterTransfer => &[(17, 666)],
            Self::EarlyDropAfterTransfer => &[(21, 888)],
            Self::SinkErrorBefore | Self::CancelBeforeTransfer | Self::EarlyDropBeforeTransfer
            | Self::Invalid => &[],
            Self::Repeat => &[(7, 111), (7, 111)],
        }
    }

    fn expected_invocations(self) -> u32 {
        if self == Self::Invalid {
            0
        } else if self == Self::Repeat {
            2
        } else {
            1
        }
    }
}

#[derive(Default)]
struct Stats {
    created: u32,
    resource_drops: u32,
    received: Vec<(u32, u32)>,
    host_calls: u32,
    pending_polls: u32,
    stream_drops: u32,
    future_drops: u32,
    cancel_calls: u32,
}

struct State {
    table: ResourceTable,
}

struct Sink {
    stats: Arc<Mutex<Stats>>,
    pending_once: bool,
    error_before: bool,
    error_after: bool,
}

impl StreamConsumer<State> for Sink {
    type Item = MixedEntry;

    fn poll_consume(
        mut self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'_, State>,
        mut source: Source<'_, Self::Item>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            self.stats
                .lock()
                .expect("mixed owned-record sink stats mutex poisoned")
                .cancel_calls += 1;
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }

        if self.error_before {
            return Poll::Ready(Ok(StreamResult::Dropped));
        }

        if self.pending_once {
            self.pending_once = false;
            self.stats
                .lock()
                .expect("mixed owned-record pending stats mutex poisoned")
                .pending_polls += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }

        let remaining = source.remaining(&mut store);
        if remaining == 0 {
            return Poll::Pending;
        }

        let mut items = Vec::with_capacity(remaining);
        source.read(&mut store, &mut items).map_err(|error| {
            wasmtime::Error::msg(format!("mixed owned-record source lift failed: {error:#}"))
        })?;
        for entry in items {
            let ticket = Resource::<Ticket>::new_own(entry.ticket.rep());
            let seed = store.data().table.get(&ticket)?.seed;
            store.data_mut().table.delete(ticket)?;
            self.stats
                .lock()
                .expect("mixed owned-record resource stats mutex poisoned")
                .resource_drops += 1;
            self.stats
                .lock()
                .expect("mixed owned-record received stats mutex poisoned")
                .received
                .push((entry.code, seed));
        }

        let outcome = if self.error_after {
            StreamResult::Dropped
        } else {
            StreamResult::Completed
        };
        Poll::Ready(Ok(outcome))
    }
}

impl Drop for Sink {
    fn drop(&mut self) {
        let mut stats = self
            .stats
            .lock()
            .expect("mixed owned-record sink drop stats mutex poisoned");
        stats.stream_drops += 1;
        stats.future_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn install_types(linker: &mut Linker<State>, stats: Arc<Mutex<Stats>>) -> wasmtime::Result<()> {
    let mut types = linker.instance(TYPES_INSTANCE)?;
    types.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        move |mut store, rep| {
            store
                .data_mut()
                .table
                .delete(Resource::<Ticket>::new_own(rep))?;
            stats
                .lock()
                .expect("mixed owned-record guest drop stats mutex poisoned")
                .resource_drops += 1;
            Ok(())
        },
    )?;
    Ok(())
}

fn install_source(linker: &mut Linker<State>, stats: Arc<Mutex<Stats>>) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_INSTANCE)?;
    source.func_wrap("make-ticket", move |mut store, (seed,): (u32,)| {
        let ticket = store.data_mut().table.push(Ticket { seed })?;
        stats
            .lock()
            .expect("mixed owned-record source stats mutex poisoned")
            .created += 1;
        Ok((ticket,))
    })?;
    Ok(())
}

fn install_sink(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: Mode,
) -> wasmtime::Result<()> {
    let mut sink = linker.instance(SINK_INSTANCE)?;
    let host_stats = Arc::clone(&stats);
    sink.func_wrap_concurrent(
        "consume-via-stream",
        move |accessor, (reader,): (StreamReader<MixedEntry>,)| {
            host_stats
                .lock()
                .expect("mixed owned-record host call stats mutex poisoned")
                .host_calls += 1;
            let stats = Arc::clone(&host_stats);
            let future = async move {
                accessor.with(|mut store| {
                    reader.pipe(
                        &mut store,
                        Sink {
                            stats: Arc::clone(&stats),
                            pending_once: mode.sink_pending(),
                            error_before: mode.sink_error_before(),
                            error_after: mode.sink_error_after(),
                        },
                    )
                })?;
                if mode.hold_call() {
                    futures::future::pending::<()>().await;
                }
                let result = if mode.sink_error_before() || mode.sink_error_after() {
                    Err(ErrorCode::Pipe)
                } else {
                    Ok(())
                };
                Ok::<(std::result::Result<(), ErrorCode>,), wasmtime::Error>((result,))
            };
            Box::pin(future)
        },
    )?;
    Ok(())
}

async fn call_produce(
    store: &mut Store<State>,
    produce: &wasmtime::component::TypedFunc<(u32,), (std::result::Result<(), ErrorCode>,)>,
    input: u32,
) -> Result<(std::result::Result<(), ErrorCode>,)> {
    Ok(map_wasmtime(map_wasmtime(
        store
            .run_concurrent(async |accessor| {
                produce.call_concurrent(&accessor, (input,)).await
            })
            .await,
    )?)?)
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
    let mut linker: Linker<State> = Linker::new(&engine);
    map_wasmtime(install_types(&mut linker, Arc::clone(&stats)))?;
    map_wasmtime(install_source(&mut linker, Arc::clone(&stats)))?;
    let sink_mode = if mode == Mode::Repeat {
        Mode::Ready
    } else {
        mode
    };
    map_wasmtime(install_sink(&mut linker, Arc::clone(&stats), sink_mode))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let produce = map_wasmtime(
        instance
            .get_typed_func::<(u32,), (std::result::Result<(), ErrorCode>,)>(&mut store, "produce"),
    )?;

    let result = if mode == Mode::Repeat {
        let first = call_produce(&mut store, &produce, Mode::Ready.input()).await?;
        if first.0 != Ok(()) {
            bail!("repeat first invocation returned {:?}", first.0);
        }
        call_produce(&mut store, &produce, Mode::Ready.input()).await?
    } else {
        call_produce(&mut store, &produce, mode.input()).await?
    };

    let snapshot = stats.lock().expect("mixed owned-record final stats mutex poisoned");
    let expected_result = mode.expected_result();
    let expected_created = mode.expected_invocations();
    let expected_received = mode.expected_received();
    let expected_host_calls = expected_created;
    let expected_pending = u32::from(mode == Mode::Pending);
    let expected_stream_drops = expected_created;
    let expected_future_drops = expected_created;
    let expected_resource_drops = expected_created;
    let table_empty = store.data().table.is_empty();
    if result.0 != expected_result
        || snapshot.received.as_slice() != expected_received
        || snapshot.created != expected_created
        || snapshot.resource_drops != expected_resource_drops
        || snapshot.host_calls != expected_host_calls
        || snapshot.stream_drops != expected_stream_drops
        || snapshot.future_drops != expected_future_drops
        || snapshot.pending_polls != expected_pending
        || snapshot.cancel_calls != 0
        || !table_empty
    {
        bail!(
            "mixed owned-record ABI mismatch mode={} result={:?} expected={:?} received={:?} expected-received={:?} resource-created={} resource-drops={} host-calls={} stream-drops={} future-drops={} pending-polls={} cancel-calls={} table-empty={}",
            mode.label(),
            result.0,
            expected_result,
            snapshot.received,
            expected_received,
            snapshot.created,
            snapshot.resource_drops,
            snapshot.host_calls,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.pending_polls,
            snapshot.cancel_calls,
            table_empty,
        );
    }

    println!(
        "mode={} received={:?} resource-created={} resource-drops={} host-calls={} stream-drops={} future-drops={} pending-polls={} cancel-calls={} table-empty=true result={:?} layout=record-offset:{} record-byte-size:{} record-alignment:{} code-offset:{} ticket-offset:{} stream-capacity:{}",
        mode.label(),
        snapshot.received,
        snapshot.created,
        snapshot.resource_drops,
        snapshot.host_calls,
        snapshot.stream_drops,
        snapshot.future_drops,
        snapshot.pending_polls,
        snapshot.cancel_calls,
        result.0,
        RECORD_OFFSET,
        RECORD_BYTE_SIZE,
        RECORD_ALIGNMENT,
        RECORD_CODE_OFFSET,
        RECORD_TICKET_OFFSET,
        STREAM_CAPACITY,
    );
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: g6_2_mixed_owned_record_producer_abi <component.wasm> <mode>")?;
    let mode = Mode::parse(
        &std::env::args()
            .nth(2)
            .context("missing mixed owned-record producer mode")?,
    )?;
    futures::executor::block_on(run(Path::new(&component_path), mode))
}
