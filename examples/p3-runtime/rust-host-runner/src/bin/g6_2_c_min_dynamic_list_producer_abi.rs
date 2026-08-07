use anyhow::{bail, Context, Result};
use futures::future::{select, Either};
use futures::pin_mut;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use std::thread;
use std::time::Duration;
use wasmtime::component::{
    Component, Linker, Resource, ResourceTable, ResourceType, Source, StreamConsumer, StreamReader,
    StreamResult,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const TYPES_INSTANCE: &str = "do:g6-2-c-min-dynamic-producer/types@0.1.0";
const SOURCE_INSTANCE: &str = "do:g6-2-c-min-dynamic-producer/source@0.1.0";
const SINK_INSTANCE: &str = "do:g6-2-c-min-dynamic-producer/sink@0.1.0";

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
struct ResourceEntry {
    ticket: Resource<Ticket>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    ReadyEmpty,
    ReadyOne,
    ReadyTwo,
    ReadyThree,
    Pending,
    SinkError,
    EarlyDrop,
    InvalidMode,
    CancelBeforeTransfer,
    CancelAfterTransfer,
    MalformedLen,
    DuplicateDrop,
    SourcePartialFailure,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "ready-empty" => Ok(Self::ReadyEmpty),
            "ready-one" => Ok(Self::ReadyOne),
            "ready-two" => Ok(Self::ReadyTwo),
            "ready-three" => Ok(Self::ReadyThree),
            "pending" => Ok(Self::Pending),
            "sink-error" => Ok(Self::SinkError),
            "early-drop" => Ok(Self::EarlyDrop),
            "invalid-mode" => Ok(Self::InvalidMode),
            "cancel-before-transfer" => Ok(Self::CancelBeforeTransfer),
            "cancel-after-transfer" => Ok(Self::CancelAfterTransfer),
            "malformed-len" => Ok(Self::MalformedLen),
            "duplicate-drop" => Ok(Self::DuplicateDrop),
            "source-partial-failure" => Ok(Self::SourcePartialFailure),
            other => bail!("unknown mode {other}"),
        }
    }

    fn input(self) -> u32 {
        match self {
            Self::ReadyEmpty => 0,
            Self::ReadyOne => 1,
            Self::ReadyTwo => 2,
            Self::ReadyThree
            | Self::Pending
            | Self::SinkError
            | Self::EarlyDrop
            | Self::CancelBeforeTransfer
            | Self::CancelAfterTransfer
            | Self::MalformedLen
            | Self::DuplicateDrop
            | Self::SourcePartialFailure => 3,
            Self::InvalidMode => 4,
        }
    }

    fn expected(self) -> &'static [u32] {
        match self {
            Self::ReadyEmpty => &[],
            Self::ReadyOne => &[1],
            Self::ReadyTwo => &[1, 2],
            Self::ReadyThree
            | Self::Pending
            | Self::SinkError
            | Self::EarlyDrop
            | Self::CancelAfterTransfer
            | Self::MalformedLen
            | Self::DuplicateDrop => &[1, 2, 3],
            Self::CancelBeforeTransfer | Self::InvalidMode => &[],
            Self::SourcePartialFailure => &[],
        }
    }

    fn sink_pending(self) -> bool {
        matches!(self, Self::Pending)
    }

    fn sink_error(self) -> bool {
        matches!(self, Self::SinkError)
    }

    fn sink_early_drop(self) -> bool {
        matches!(self, Self::EarlyDrop)
    }

    fn cancellation(self) -> bool {
        matches!(self, Self::CancelAfterTransfer)
    }

    fn label(self) -> &'static str {
        match self {
            Self::ReadyEmpty => "ready-empty",
            Self::ReadyOne => "ready-one",
            Self::ReadyTwo => "ready-two",
            Self::ReadyThree => "ready-three",
            Self::Pending => "pending",
            Self::SinkError => "sink-error",
            Self::EarlyDrop => "early-drop",
            Self::InvalidMode => "invalid-mode",
            Self::CancelBeforeTransfer => "cancel-before-transfer",
            Self::CancelAfterTransfer => "cancel-after-transfer",
            Self::MalformedLen => "malformed-len",
            Self::DuplicateDrop => "duplicate-drop",
            Self::SourcePartialFailure => "source-partial-failure",
        }
    }
}

#[derive(Default)]
struct Stats {
    created: u32,
    source_failures: u32,
    resource_drops: u32,
    received: Vec<u32>,
    host_calls: u32,
    pending_polls: u32,
    stream_drops: u32,
    cancel_calls: u32,
}

struct State {
    table: ResourceTable,
}

struct Sink {
    stats: Arc<Mutex<Stats>>,
    pending_once: bool,
    error: bool,
    early_drop: bool,
    transfer_sender: Option<futures::channel::oneshot::Sender<()>>,
}

impl StreamConsumer<State> for Sink {
    type Item = Vec<ResourceEntry>;

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
                .expect("c-min sink stats mutex poisoned")
                .cancel_calls += 1;
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }

        if self.pending_once {
            self.pending_once = false;
            self.stats
                .lock()
                .expect("c-min sink stats mutex poisoned")
                .pending_polls += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }

        let remaining = source.remaining(&mut store);
        let mut items = Vec::with_capacity(remaining);
        source.read(&mut store, &mut items).map_err(|error| {
            wasmtime::Error::msg(format!("c-min source list lift failed: {error:#}"))
        })?;
        for entries in items {
            for entry in entries {
                let ticket = Resource::<Ticket>::new_own(entry.ticket.rep());
                let seed = store.data().table.get(&ticket)?.seed;
                store.data_mut().table.delete(ticket)?;
                self.stats
                    .lock()
                    .expect("c-min sink stats mutex poisoned")
                    .received
                    .push(seed);
            }
        }
        if let Some(sender) = self.transfer_sender.take() {
            let _ = sender.send(());
        }
        if self.error || self.early_drop {
            Poll::Ready(Ok(StreamResult::Dropped))
        } else {
            Poll::Ready(Ok(StreamResult::Completed))
        }
    }
}

impl Drop for Sink {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("c-min sink stats mutex poisoned")
            .stream_drops += 1;
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
                .expect("c-min type drop stats mutex poisoned")
                .resource_drops += 1;
            Ok(())
        },
    )?;
    Ok(())
}

fn install_source(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: Mode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_INSTANCE)?;
    source.func_wrap("make-ticket", move |mut store, (seed,): (u32,)| {
        if mode == Mode::SourcePartialFailure && seed == 3 {
            stats
                .lock()
                .expect("dynamic source stats mutex poisoned")
                .source_failures += 1;
            return Ok((Resource::new_own(0),));
        }
        let ticket = store.data_mut().table.push(Ticket { seed })?;
        stats
            .lock()
            .expect("c-min source stats mutex poisoned")
            .created += 1;
        Ok((ticket,))
    })?;
    Ok(())
}

fn install_sink(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: Mode,
    transfer_sender: futures::channel::oneshot::Sender<()>,
) -> wasmtime::Result<()> {
    let mut sink = linker.instance(SINK_INSTANCE)?;
    let host_stats = Arc::clone(&stats);
    let transfer_sender = Arc::new(Mutex::new(Some(transfer_sender)));
    sink.func_wrap_concurrent(
        "consume-via-stream",
        move |accessor, (reader,): (StreamReader<Vec<ResourceEntry>>,)| {
            host_stats
                .lock()
                .expect("c-min host stats mutex poisoned")
                .host_calls += 1;
            let stats = Arc::clone(&host_stats);
            let transfer_sender = transfer_sender
                .lock()
                .expect("c-min transfer sender mutex poisoned")
                .take();
            Box::pin(async move {
                if mode == Mode::CancelBeforeTransfer {
                    futures::future::pending::<()>().await;
                }
                accessor.with(|mut store| {
                    reader.pipe(
                        &mut store,
                        Sink {
                            stats: Arc::clone(&stats),
                            pending_once: mode.sink_pending(),
                            error: mode.sink_error(),
                            early_drop: mode.sink_early_drop(),
                            transfer_sender,
                        },
                    )
                })?;
                if mode == Mode::CancelAfterTransfer {
                    futures::future::pending::<()>().await;
                }
                Ok::<(std::result::Result<(), ErrorCode>,), wasmtime::Error>((
                    if mode.sink_error() {
                        Err(ErrorCode::Pipe)
                    } else {
                        Ok(())
                    },
                ))
            })
        },
    )?;
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
    let mut linker: Linker<State> = Linker::new(&engine);
    map_wasmtime(install_types(&mut linker, Arc::clone(&stats)))?;
    map_wasmtime(install_source(&mut linker, Arc::clone(&stats), mode))?;
    let (transfer_sender, transfer_receiver) = futures::channel::oneshot::channel();
    map_wasmtime(install_sink(
        &mut linker,
        Arc::clone(&stats),
        mode,
        transfer_sender,
    ))?;
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
    let result = if mode.cancellation() {
        let call = store.run_concurrent(async |accessor| {
            produce.call_concurrent(&accessor, (mode.input(),)).await
        });
        pin_mut!(call);
        let cancel_gate = transfer_receiver;
        pin_mut!(cancel_gate);
        match select(call, cancel_gate).await {
            Either::Left((result, _)) => {
                let result = map_wasmtime(map_wasmtime(result)?)?;
                bail!(
                    "c-min cancellation completed before cancellation mode={mode:?} result={result:?}"
                );
            }
            Either::Right((_, pending_call)) => {
                drop(pending_call);
                thread::sleep(Duration::from_millis(25));
                None
            }
        }
    } else {
        Some(map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |accessor| {
                    produce.call_concurrent(&accessor, (mode.input(),)).await
                })
                .await,
        )?)?)
    };

    let snapshot = stats.lock().expect("c-min final stats mutex poisoned");
    let expected_result = if mode == Mode::SourcePartialFailure {
        Err(ErrorCode::Io)
    } else if matches!(mode, Mode::SinkError | Mode::EarlyDrop) {
        Err(ErrorCode::Pipe)
    } else if mode == Mode::InvalidMode {
        Err(ErrorCode::InvalidMode)
    } else {
        Ok(())
    };
    let result_matches = result
        .as_ref()
        .map_or(true, |value| value.0 == expected_result);
    let no_host_call = matches!(mode, Mode::InvalidMode | Mode::SourcePartialFailure);
    if !result_matches
        || (no_host_call && !snapshot.received.is_empty())
        || (!no_host_call && snapshot.received != mode.expected())
        || (mode == Mode::InvalidMode && snapshot.created != 0)
        || (mode == Mode::SourcePartialFailure && snapshot.created != 2)
        || snapshot.host_calls != u32::from(!no_host_call)
        || snapshot.stream_drops
            != if matches!(
                mode,
                Mode::CancelBeforeTransfer | Mode::InvalidMode | Mode::SourcePartialFailure
            ) {
                0
            } else {
                1
            }
        || (mode == Mode::CancelBeforeTransfer && snapshot.resource_drops != 3)
        || (mode == Mode::SourcePartialFailure && snapshot.resource_drops != 2)
        || (mode == Mode::CancelAfterTransfer && snapshot.resource_drops != 0)
        || !store.data().table.is_empty()
    {
        bail!(
            "c-min mismatch mode={} result={result:?} expected={expected_result:?} received={:?} expected-items={:?} host-calls={} pending-polls={} stream-drops={} created={} resource-drops={} cancel-calls={} table-empty={}",
            mode.label(),
            snapshot.received,
            mode.expected(),
            snapshot.host_calls,
            snapshot.pending_polls,
            snapshot.stream_drops,
            snapshot.created,
            snapshot.resource_drops,
            snapshot.cancel_calls,
            store.data().table.is_empty(),
        );
    }
    println!(
        "mode={} result={result:?} entries={:?} expected={:?} host-calls={} pending-polls={} stream-drops={} resource-created={} resource-drops={} cancel-calls={} table-empty=true",
        mode.label(),
        snapshot.received,
        mode.expected(),
        snapshot.host_calls,
        snapshot.pending_polls,
        snapshot.stream_drops,
        snapshot.created,
        snapshot.resource_drops,
        snapshot.cancel_calls,
    );
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: g6_2_c_min_list_resource_producer_abi <component.wasm> <mode>")?;
    let mode = Mode::parse(&std::env::args().nth(2).context("missing c-min mode")?)?;
    futures::executor::block_on(run(Path::new(&component_path), mode))
}
