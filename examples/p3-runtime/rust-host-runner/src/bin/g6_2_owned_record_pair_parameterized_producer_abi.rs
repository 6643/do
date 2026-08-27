use anyhow::{Context, Result, bail};
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Linker, Resource, ResourceTable, ResourceType, Source, StreamConsumer, StreamReader,
    StreamResult,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const TYPES_INSTANCE: &str = "do:g6-2-owned-record-pair-parameterized-producer/types@0.1.0";
const SOURCE_INSTANCE: &str = "do:g6-2-owned-record-pair-parameterized-producer/source@0.1.0";
const SINK_INSTANCE: &str = "do:g6-2-owned-record-pair-parameterized-producer/sink@0.1.0";

const RECORD_OFFSET: u32 = 64;
const RECORD_BYTE_SIZE: u32 = 8;
const RECORD_LEFT_OFFSET: u32 = 0;
const RECORD_RIGHT_OFFSET: u32 = 4;
const STREAM_CAPACITY: u32 = 1;
const REPEAT_SECOND_LEFT_SEED: u32 = 333;
const REPEAT_SECOND_RIGHT_SEED: u32 = 444;

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
struct ResourcePair {
    left: Resource<Ticket>,
    right: Resource<Ticket>,
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
            Self::SinkErrorBefore
            | Self::SinkErrorAfter
            | Self::CancelBeforeTransfer
            | Self::CancelAfterTransfer
            | Self::EarlyDropBeforeTransfer
            | Self::EarlyDropAfterTransfer => Err(ErrorCode::Pipe),
        }
    }

    fn expected_received(self, left_seed: u32, right_seed: u32) -> Vec<u32> {
        match self {
            Self::Ready
            | Self::Pending
            | Self::SinkErrorAfter
            | Self::CancelAfterTransfer
            | Self::EarlyDropAfterTransfer => vec![left_seed, right_seed],
            Self::SinkErrorBefore
            | Self::CancelBeforeTransfer
            | Self::EarlyDropBeforeTransfer
            | Self::Invalid => Vec::new(),
            Self::Repeat => vec![
                left_seed,
                right_seed,
                REPEAT_SECOND_LEFT_SEED,
                REPEAT_SECOND_RIGHT_SEED,
            ],
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
    received: Vec<u32>,
    host_calls: u32,
    callback_calls: u32,
    poll_calls: u32,
    finish_calls: u32,
    pending_polls: u32,
    stream_drops: u32,
    future_drops: u32,
    future_polls: u32,
    future_completions: u32,
    pending_future_drops: u32,
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

type HostFutureOutput = wasmtime::Result<(std::result::Result<(), ErrorCode>,)>;

struct ObservedHostFuture<F> {
    inner: Pin<Box<F>>,
    stats: Arc<Mutex<Stats>>,
    completed: bool,
}

impl<F> ObservedHostFuture<F> {
    fn new(inner: Pin<Box<F>>, stats: Arc<Mutex<Stats>>) -> Self {
        Self {
            inner,
            stats,
            completed: false,
        }
    }
}

impl<F> Future for ObservedHostFuture<F>
where
    F: Future<Output = HostFutureOutput> + Send,
{
    type Output = HostFutureOutput;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        let poll = self.inner.as_mut().poll(cx);
        let completed = poll.is_ready();
        if completed {
            self.completed = true;
        }
        let mut stats = self
            .stats
            .lock()
            .expect("owned record pair host future stats mutex poisoned");
        stats.future_polls += 1;
        if completed {
            stats.future_completions += 1;
        }
        poll
    }
}

impl<F> Drop for ObservedHostFuture<F> {
    fn drop(&mut self) {
        let mut stats = self
            .stats
            .lock()
            .expect("owned record pair host future drop stats mutex poisoned");
        stats.future_drops += 1;
        if !self.completed {
            stats.pending_future_drops += 1;
            stats.cancel_calls += 1;
        }
    }
}

impl StreamConsumer<State> for Sink {
    type Item = ResourcePair;

    fn poll_consume(
        mut self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'_, State>,
        mut source: Source<'_, Self::Item>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        self.stats
            .lock()
            .expect("owned record pair sink callback stats mutex poisoned")
            .poll_calls += 1;
        if finish {
            self.stats
                .lock()
                .expect("owned record pair sink finish stats mutex poisoned")
                .finish_calls += 1;
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }

        if self.error_before {
            return Poll::Ready(Ok(StreamResult::Dropped));
        }

        if self.pending_once {
            self.pending_once = false;
            self.stats
                .lock()
                .expect("owned record pair pending stats mutex poisoned")
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
            wasmtime::Error::msg(format!("owned record pair source lift failed: {error:#}"))
        })?;
        for entry in items {
            for ticket in [entry.left, entry.right] {
                let ticket = Resource::<Ticket>::new_own(ticket.rep());
                let seed = store.data().table.get(&ticket)?.seed;
                store.data_mut().table.delete(ticket)?;
                self.stats
                    .lock()
                    .expect("owned record pair resource stats mutex poisoned")
                    .resource_drops += 1;
                self.stats
                    .lock()
                    .expect("owned record pair received stats mutex poisoned")
                    .received
                    .push(seed);
            }
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
            .expect("owned record pair sink drop stats mutex poisoned");
        stats.stream_drops += 1;
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
                .expect("owned record pair guest drop stats mutex poisoned")
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
            .expect("owned record pair source stats mutex poisoned")
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
        move |accessor, (reader,): (StreamReader<ResourcePair>,)| {
            {
                let mut stats = host_stats
                    .lock()
                    .expect("owned record pair host callback stats mutex poisoned");
                stats.host_calls += 1;
                stats.callback_calls += 1;
            }
            let stats = Arc::clone(&host_stats);
            let future_stats = Arc::clone(&stats);
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
            Box::pin(ObservedHostFuture::new(Box::pin(future), future_stats))
        },
    )?;
    Ok(())
}

async fn call_produce(
    store: &mut Store<State>,
    produce: &wasmtime::component::TypedFunc<(u32, u32, u32), (std::result::Result<(), ErrorCode>,)>,
    mode: u32,
    left_seed: u32,
    right_seed: u32,
) -> Result<(std::result::Result<(), ErrorCode>,)> {
    Ok(map_wasmtime(map_wasmtime(
        store
            .run_concurrent(async |accessor| {
                produce
                    .call_concurrent(&accessor, (mode, left_seed, right_seed))
                    .await
            })
            .await,
    )?)?)
}

async fn run(component_path: &Path, mode: Mode, left_seed: u32, right_seed: u32) -> Result<()> {
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
        instance.get_typed_func::<
            (u32, u32, u32),
            (std::result::Result<(), ErrorCode>,),
        >(&mut store, "produce"),
    )?;

    let result = if mode == Mode::Repeat {
        let first = call_produce(
            &mut store,
            &produce,
            Mode::Ready.input(),
            left_seed,
            right_seed,
        )
        .await?;
        if first.0 != Ok(()) {
            bail!("repeat first invocation returned {:?}", first.0);
        }
        call_produce(
            &mut store,
            &produce,
            Mode::Ready.input(),
            REPEAT_SECOND_LEFT_SEED,
            REPEAT_SECOND_RIGHT_SEED,
        )
        .await?
    } else {
        call_produce(
            &mut store,
            &produce,
            mode.input(),
            left_seed,
            right_seed,
        )
        .await?
    };

    let snapshot = stats
        .lock()
        .expect("owned record pair final stats mutex poisoned");
    let expected_result = mode.expected_result();
    let expected_invocations = mode.expected_invocations();
    let expected_created = expected_invocations * 2;
    let expected_received = mode.expected_received(left_seed, right_seed);
    let expected_host_calls = expected_invocations;
    let expected_pending = u32::from(mode == Mode::Pending);
    let expected_stream_drops = expected_invocations;
    let expected_future_drops = expected_invocations;
    let expected_callback_calls = expected_invocations;
    let expected_poll_calls = match mode {
        Mode::Invalid => 0,
        Mode::Repeat => 2,
        Mode::Pending => 2,
        Mode::CancelBeforeTransfer | Mode::EarlyDropBeforeTransfer => 0,
        _ => 1,
    };
    let expected_finish_calls = 0;
    let expected_future_completions = match mode {
        Mode::CancelBeforeTransfer
        | Mode::CancelAfterTransfer
        | Mode::EarlyDropBeforeTransfer
        | Mode::EarlyDropAfterTransfer => 0,
        Mode::Invalid => 0,
        _ => expected_invocations,
    };
    let expected_pending_future_drops = match mode {
        Mode::CancelBeforeTransfer
        | Mode::CancelAfterTransfer
        | Mode::EarlyDropBeforeTransfer
        | Mode::EarlyDropAfterTransfer => expected_invocations,
        _ => 0,
    };
    let expected_cancel_calls = expected_pending_future_drops;
    let expected_resource_drops = expected_created;
    let table_empty = store.data().table.is_empty();
    if result.0 != expected_result
        || snapshot.received != expected_received
        || snapshot.created != expected_created
        || snapshot.resource_drops != expected_resource_drops
        || snapshot.host_calls != expected_host_calls
        || snapshot.stream_drops != expected_stream_drops
        || snapshot.future_drops != expected_future_drops
        || snapshot.callback_calls != expected_callback_calls
        || snapshot.poll_calls != expected_poll_calls
        || snapshot.finish_calls != expected_finish_calls
        || snapshot.future_completions != expected_future_completions
        || snapshot.pending_future_drops != expected_pending_future_drops
        || snapshot.pending_polls != expected_pending
        || snapshot.cancel_calls != expected_cancel_calls
        || !table_empty
    {
        bail!(
            "owned record pair ABI mismatch mode={} result={:?} expected={:?} received={:?} expected-received={:?} resource-created={} resource-drops={} host-calls={} callback-calls={} poll-calls={} finish-calls={} stream-drops={} future-drops={} future-polls={} future-completions={} pending-future-drops={} pending-polls={} cancel-calls={} table-empty={}",
            mode.label(),
            result.0,
            expected_result,
            snapshot.received,
            expected_received,
            snapshot.created,
            snapshot.resource_drops,
            snapshot.host_calls,
            snapshot.callback_calls,
            snapshot.poll_calls,
            snapshot.finish_calls,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.future_polls,
            snapshot.future_completions,
            snapshot.pending_future_drops,
            snapshot.pending_polls,
            snapshot.cancel_calls,
            table_empty,
        );
    }

    println!(
        "mode={} received={:?} resource-created={} resource-drops={} host-calls={} callback-calls={} poll-calls={} finish-calls={} stream-drops={} future-drops={} future-polls={} future-completions={} pending-future-drops={} pending-polls={} cancel-calls={} table-empty=true result={:?} layout=record-offset:{} record-byte-size:{} left-offset:{} right-offset:{} stream-capacity:{} left-ticket-seed:{} right-ticket-seed:{}",
        mode.label(),
        snapshot.received,
        snapshot.created,
        snapshot.resource_drops,
        snapshot.host_calls,
        snapshot.callback_calls,
        snapshot.poll_calls,
        snapshot.finish_calls,
        snapshot.stream_drops,
        snapshot.future_drops,
        snapshot.future_polls,
        snapshot.future_completions,
        snapshot.pending_future_drops,
        snapshot.pending_polls,
        snapshot.cancel_calls,
        result.0,
        RECORD_OFFSET,
        RECORD_BYTE_SIZE,
        RECORD_LEFT_OFFSET,
        RECORD_RIGHT_OFFSET,
        STREAM_CAPACITY,
        left_seed,
        right_seed,
    );
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context(
            "usage: g6_2_owned_record_pair_parameterized_producer_abi <component.wasm> <mode> <left-seed> <right-seed>",
        )?;
    let mode = Mode::parse(
        &std::env::args()
            .nth(2)
            .context("missing owned record pair producer mode")?,
    )?;
    let left_seed = std::env::args()
        .nth(3)
        .context("missing left ticket seed")?
        .parse::<u32>()
        .context("left ticket seed must be u32")?;
    let right_seed = std::env::args()
        .nth(4)
        .context("missing right ticket seed")?
        .parse::<u32>()
        .context("right ticket seed must be u32")?;
    futures::executor::block_on(run(Path::new(&component_path), mode, left_seed, right_seed))
}
