use anyhow::{Context, Result, bail};
use futures::future::{Either, select};
use futures::pin_mut;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use std::thread;
use std::time::Duration;
use wasmtime::component::{
    Component, Linker, ResourceTable, Source, StreamConsumer, StreamReader, StreamResult,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const SINK_INSTANCE: &str = "do:g6-2-scalar-list-producer/sink@0.1.0";

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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Count0,
    Count1,
    Count2,
    Count3,
    Count4,
    Pending,
    SinkError,
    EarlyDrop,
    CancelBeforeTransfer,
    CancelAfterTransfer,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "count-0" => Ok(Self::Count0),
            "count-1" => Ok(Self::Count1),
            "count-2" => Ok(Self::Count2),
            "count-3" => Ok(Self::Count3),
            "count-4" => Ok(Self::Count4),
            "pending" => Ok(Self::Pending),
            "sink-error" => Ok(Self::SinkError),
            "early-drop" => Ok(Self::EarlyDrop),
            "cancel-before-transfer" => Ok(Self::CancelBeforeTransfer),
            "cancel-after-transfer" => Ok(Self::CancelAfterTransfer),
            other => bail!("unknown mode {other}"),
        }
    }

    fn input(self) -> u32 {
        match self {
            Self::Count0 => 0,
            Self::Count1 => 1,
            Self::Count2 => 2,
            Self::Count3 => 3,
            Self::Count4 => 4,
            Self::Pending => 10,
            Self::SinkError => 11,
            Self::EarlyDrop => 12,
            Self::CancelBeforeTransfer => 13,
            Self::CancelAfterTransfer => 14,
        }
    }

    fn expected(self) -> &'static [u32] {
        match self {
            Self::Count0 | Self::Count4 | Self::CancelBeforeTransfer => &[],
            Self::Count1 => &[10],
            Self::Count2 => &[10, 20],
            Self::Count3
            | Self::Pending
            | Self::SinkError
            | Self::EarlyDrop
            | Self::CancelAfterTransfer => &[10, 20, 30],
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

    fn expects_invalid(self) -> bool {
        matches!(self, Self::Count4)
    }

    fn label(self) -> &'static str {
        match self {
            Self::Count0 => "count-0",
            Self::Count1 => "count-1",
            Self::Count2 => "count-2",
            Self::Count3 => "count-3",
            Self::Count4 => "count-4",
            Self::Pending => "pending",
            Self::SinkError => "sink-error",
            Self::EarlyDrop => "early-drop",
            Self::CancelBeforeTransfer => "cancel-before-transfer",
            Self::CancelAfterTransfer => "cancel-after-transfer",
        }
    }
}

#[derive(Default)]
struct Stats {
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
    type Item = Vec<u32>;

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
                .expect("scalar-list sink stats mutex poisoned")
                .cancel_calls += 1;
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }

        if self.pending_once {
            self.pending_once = false;
            self.stats
                .lock()
                .expect("scalar-list sink stats mutex poisoned")
                .pending_polls += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }

        let remaining = source.remaining(&mut store);
        let mut items = Vec::with_capacity(remaining);
        source.read(&mut store, &mut items).map_err(|error| {
            wasmtime::Error::msg(format!("scalar-list source lift failed: {error:#}"))
        })?;
        for values in items {
            self.stats
                .lock()
                .expect("scalar-list sink stats mutex poisoned")
                .received
                .extend(values);
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
            .expect("scalar-list sink stats mutex poisoned")
            .stream_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
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
        move |accessor, (reader,): (StreamReader<Vec<u32>>,)| {
            host_stats
                .lock()
                .expect("scalar-list host stats mutex poisoned")
                .host_calls += 1;
            let stats = Arc::clone(&host_stats);
            let transfer_sender = transfer_sender
                .lock()
                .expect("scalar-list transfer sender mutex poisoned")
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
                    "scalar-list cancellation completed before cancellation mode={mode:?} result={result:?}"
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

    let snapshot = stats
        .lock()
        .expect("scalar-list final stats mutex poisoned");
    let expected_result = if matches!(mode, Mode::SinkError | Mode::EarlyDrop) {
        Err(ErrorCode::Pipe)
    } else if mode.expects_invalid() {
        Err(ErrorCode::InvalidMode)
    } else {
        Ok(())
    };
    let result_matches = result
        .as_ref()
        .map_or(true, |value| value.0 == expected_result);
    if !result_matches
        || (!mode.expects_invalid() && snapshot.received != mode.expected())
        || snapshot.host_calls != u32::from(!mode.expects_invalid())
        || snapshot.stream_drops
            != if mode == Mode::CancelBeforeTransfer {
                0
            } else {
                u32::from(!mode.expects_invalid())
            }
        || snapshot.pending_polls != u32::from(mode == Mode::Pending)
        || !store.data().table.is_empty()
    {
        bail!(
            "scalar-list mismatch mode={} result={result:?} expected={expected_result:?} received={:?} expected-items={:?} host-calls={} pending-polls={} stream-drops={} cancel-calls={} list-releases={} table-empty={}",
            mode.label(),
            snapshot.received,
            mode.expected(),
            snapshot.host_calls,
            snapshot.pending_polls,
            snapshot.stream_drops,
            snapshot.cancel_calls,
            u32::from(!mode.expects_invalid()),
            store.data().table.is_empty(),
        );
    }
    println!(
        "mode={} result={result:?} values={:?} expected={:?} host-calls={} pending-polls={} stream-drops={} cancel-calls={} list-releases={} table-empty=true",
        mode.label(),
        snapshot.received,
        mode.expected(),
        snapshot.host_calls,
        snapshot.pending_polls,
        snapshot.stream_drops,
        snapshot.cancel_calls,
        u32::from(!mode.expects_invalid()),
    );
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: g6_2_scalar_list_producer_abi <component.wasm> <mode>")?;
    let mode = Mode::parse(
        &std::env::args()
            .nth(2)
            .context("missing scalar-list mode")?,
    )?;
    futures::executor::block_on(run(Path::new(&component_path), mode))
}
