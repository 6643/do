use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use futures::future::{Either, select};
use futures::pin_mut;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use std::thread;
use std::time::Duration;
use wasmtime::component::{Component, Linker, Source, StreamConsumer, StreamResult};
use wasmtime::{Config, Engine, Store};

const SINK_INSTANCE: &str = "do:stream-probe/sink@0.1.0";

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
    #[component(name = "illegal-byte-sequence")]
    IllegalByteSequence,
    #[component(name = "pipe")]
    Pipe,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Mode {
    Pending,
    Ready,
    Error,
    Abort,
    CancelAfterTransfer,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ProducerShape {
    Countdown,
    Parameterized,
    ParameterizedHelper,
    ParameterizedThreeHop,
    ParameterizedFourHop,
    ParameterizedFiveHop,
    ParameterizedSixHop,
    BranchTerminal,
}

impl ProducerShape {
    fn parse(value: Option<&str>) -> Result<Self> {
        match value {
            None => Ok(Self::Countdown),
            Some("parameterized") => Ok(Self::Parameterized),
            Some("parameterized-helper") => Ok(Self::ParameterizedHelper),
            Some("parameterized-three-hop") => Ok(Self::ParameterizedThreeHop),
            Some("parameterized-four-hop") => Ok(Self::ParameterizedFourHop),
            Some("parameterized-five-hop") => Ok(Self::ParameterizedFiveHop),
            Some("parameterized-six-hop") => Ok(Self::ParameterizedSixHop),
            Some("branch-terminal") => Ok(Self::BranchTerminal),
            Some(other) => bail!(
                "unknown producer shape {other}; expected parameterized, parameterized-helper, parameterized-three-hop, parameterized-four-hop, parameterized-five-hop, parameterized-six-hop, or branch-terminal"
            ),
        }
    }

    fn is_parameterized(self) -> bool {
        matches!(
            self,
            Self::Parameterized
                | Self::ParameterizedHelper
                | Self::ParameterizedThreeHop
                | Self::ParameterizedFourHop
                | Self::ParameterizedFiveHop
                | Self::ParameterizedSixHop
                | Self::BranchTerminal
        )
    }

    fn label(self) -> &'static str {
        match self {
            Self::Countdown => "countdown",
            Self::Parameterized => "parameterized",
            Self::ParameterizedHelper => "parameterized-helper",
            Self::ParameterizedThreeHop => "parameterized-three-hop",
            Self::ParameterizedFourHop => "parameterized-four-hop",
            Self::ParameterizedFiveHop => "parameterized-five-hop",
            Self::ParameterizedSixHop => "parameterized-six-hop",
            Self::BranchTerminal => "branch-terminal",
        }
    }
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "pending" => Ok(Self::Pending),
            "ready" => Ok(Self::Ready),
            "error" => Ok(Self::Error),
            "abort" => Ok(Self::Abort),
            "cancel-after-transfer" => Ok(Self::CancelAfterTransfer),
            other => bail!("unknown mode {other}; expected pending, ready, error, or abort"),
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Ready => "ready",
            Self::Error => "err:pipe",
            Self::Abort => "abort:pipe",
            Self::CancelAfterTransfer => "cancel-after-transfer",
        }
    }
}

#[derive(Default)]
struct Stats {
    items: Vec<u8>,
    host_calls: u32,
    pending_polls: u32,
    stream_drops: u32,
}

struct RecordingConsumer {
    stats: Arc<Mutex<Stats>>,
    dropped: Option<oneshot::Sender<()>>,
    transferred: Option<oneshot::Sender<()>>,
    expected_items: usize,
    consumed_items: usize,
    pending_once: bool,
    hold_until_writer_drop: bool,
}

impl StreamConsumer<()> for RecordingConsumer {
    type Item = u8;

    fn poll_consume(
        self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        mut store: wasmtime::StoreContextMut<'_, ()>,
        mut source: Source<'_, Self::Item>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Dropped));
        }

        let consumer = self.get_mut();
        if consumer.expected_items == 0 && !consumer.hold_until_writer_drop {
            return Poll::Ready(Ok(StreamResult::Dropped));
        }

        let remaining = source.remaining(&mut store);
        if remaining == 0 {
            return Poll::Pending;
        }
        if consumer.pending_once {
            consumer.pending_once = false;
            consumer
                .stats
                .lock()
                .expect("dynamic producer stats mutex poisoned")
                .pending_polls += 1;
            let waker = cx.waker().clone();
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_millis(5));
                waker.wake();
            });
            return Poll::Pending;
        }

        let mut items = Vec::with_capacity(remaining);
        source.read(&mut store, &mut items)?;
        consumer.consumed_items += items.len();
        consumer
            .stats
            .lock()
            .expect("dynamic producer stats mutex poisoned")
            .items
            .extend_from_slice(&items);
        if let Some(sender) = consumer.transferred.take() {
            let _ = sender.send(());
        }
        if consumer.consumed_items >= consumer.expected_items && !consumer.hold_until_writer_drop {
            Poll::Ready(Ok(StreamResult::Dropped))
        } else {
            Poll::Ready(Ok(StreamResult::Completed))
        }
    }
}

impl Drop for RecordingConsumer {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("dynamic producer stats mutex poisoned")
            .stream_drops += 1;
        if let Some(sender) = self.dropped.take() {
            let _ = sender.send(());
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-stream-probe-guest-producer-dynamic-host-runner <component.wasm> [pending|ready|error|abort|cancel-after-transfer] [parameterized|parameterized-helper|parameterized-three-hop|parameterized-four-hop|parameterized-five-hop|parameterized-six-hop|branch-terminal]")?;
    let mode = Mode::parse(
        &std::env::args()
            .nth(2)
            .unwrap_or_else(|| "pending".to_string()),
    )?;
    let producer = ProducerShape::parse(std::env::args().nth(3).as_deref())?;
    futures::executor::block_on(run(Path::new(&component_path), mode, producer))
}

async fn run(component_path: &Path, mode: Mode, producer: ProducerShape) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);

    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let mut linker: Linker<()> = Linker::new(&engine);
    let stats = Arc::new(Mutex::new(Stats::default()));
    let expected_count = Arc::new(Mutex::new(0_usize));
    let host_stats = Arc::clone(&stats);
    let host_expected_count = Arc::clone(&expected_count);
    let transfer_signal = Arc::new(Mutex::new(None::<oneshot::Sender<()>>));
    let host_transfer_signal = Arc::clone(&transfer_signal);
    let mut sink = map_wasmtime(linker.instance(SINK_INSTANCE))?;
    map_wasmtime(sink.func_wrap_concurrent(
        "write-via-stream",
        move |accessor, (reader,): (wasmtime::component::StreamReader<u8>,)| {
            let stats = Arc::clone(&host_stats);
            let (dropped_sender, dropped_receiver) = oneshot::channel();
            let transferred_sender = host_transfer_signal
                .lock()
                .expect("dynamic transfer signal mutex poisoned")
                .take();
            stats
                .lock()
                .expect("dynamic producer stats mutex poisoned")
                .host_calls += 1;
            let expected_items = *host_expected_count
                .lock()
                .expect("dynamic producer count mutex poisoned");
            Box::pin(async move {
                accessor.with(|mut store| {
                    reader.pipe(
                        &mut store,
                        RecordingConsumer {
                            stats: Arc::clone(&stats),
                            dropped: Some(dropped_sender),
                            transferred: transferred_sender,
                            expected_items,
                            consumed_items: 0,
                            pending_once: mode == Mode::Pending,
                            hold_until_writer_drop: mode == Mode::Abort,
                        },
                    )
                })?;
                if mode == Mode::CancelAfterTransfer {
                    futures::future::pending::<()>().await;
                }
                dropped_receiver
                    .await
                    .map_err(|_| wasmtime::Error::msg("dynamic stream reader was not dropped"))?;
                let result = if mode == Mode::Error {
                    Err(ErrorCode::Pipe)
                } else {
                    Ok(())
                };
                Ok::<(std::result::Result<(), ErrorCode>,), wasmtime::Error>((result,))
            })
        },
    ))?;

    let mut store = Store::new(&engine, ());
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    if producer.is_parameterized() {
        let produce = map_wasmtime(
            instance.get_typed_func::<(u64, u8), (std::result::Result<(), ErrorCode>,)>(
                &mut store, "produce",
            ),
        )?;
        let value = if producer == ProducerShape::BranchTerminal && mode == Mode::Abort {
            91
        } else {
            90
        };
        let counts: &[u64] = if mode == Mode::CancelAfterTransfer {
            &[3]
        } else {
            &[0, 1, 3]
        };
        for count in counts {
            reset_stats(&stats, &expected_count, *count);
            if mode == Mode::CancelAfterTransfer {
                let (sender, receiver) = oneshot::channel();
                *transfer_signal
                    .lock()
                    .expect("dynamic transfer signal mutex poisoned") = Some(sender);
                let call = store.run_concurrent(async |accessor| {
                    produce.call_concurrent(&accessor, (*count, value)).await
                });
                pin_mut!(call);
                pin_mut!(receiver);
                match select(call, receiver).await {
                    Either::Left((result, _)) => {
                        let result = map_wasmtime(map_wasmtime(result)?)?;
                        bail!("cancellation completed before transfer result={result:?}");
                    }
                    Either::Right((_, pending_call)) => {
                        drop(pending_call);
                        thread::sleep(Duration::from_millis(25));
                    }
                }
                verify_cancel_run(&stats, producer, *count, value)?;
            } else {
                let result = map_wasmtime(map_wasmtime(
                    store
                        .run_concurrent(async |accessor| {
                            produce.call_concurrent(&accessor, (*count, value)).await
                        })
                        .await,
                )?)?;
                verify_run(&stats, mode, producer, *count, value, result)?;
            }
        }
    } else {
        let produce = map_wasmtime(
            instance.get_typed_func::<(u64,), (std::result::Result<(), ErrorCode>,)>(
                &mut store, "produce",
            ),
        )?;
        for count in [0_u64, 1, 3] {
            reset_stats(&stats, &expected_count, count);
            let result = map_wasmtime(map_wasmtime(
                store
                    .run_concurrent(async |accessor| {
                        produce.call_concurrent(&accessor, (count,)).await
                    })
                    .await,
            )?)?;
            verify_run(&stats, mode, producer, count, 65, result)?;
        }
    }
    Ok(())
}

fn reset_stats(stats: &Arc<Mutex<Stats>>, expected_count: &Arc<Mutex<usize>>, count: u64) {
    *stats.lock().expect("dynamic producer stats mutex poisoned") = Stats::default();
    *expected_count
        .lock()
        .expect("dynamic producer count mutex poisoned") = count as usize;
}

fn verify_run(
    stats: &Arc<Mutex<Stats>>,
    mode: Mode,
    producer: ProducerShape,
    count: u64,
    value: u8,
    result: (std::result::Result<(), ErrorCode>,),
) -> Result<()> {
    let stats = stats.lock().expect("dynamic producer stats mutex poisoned");
    let expected = vec![value; count as usize];
    let expected_result = if matches!(mode, Mode::Error | Mode::Abort) {
        Err(ErrorCode::Pipe)
    } else {
        Ok(())
    };
    if result.0 != expected_result
        || stats.items != expected
        || stats.host_calls != 1
        || stats.stream_drops != 1
        || (mode == Mode::Pending && stats.pending_polls != if count == 0 { 0 } else { 1 })
        || (mode != Mode::Pending && stats.pending_polls != 0)
    {
        bail!(
            "dynamic producer mismatch producer={} mode={} count={} result={result:?} items={:?} host-calls={} pending-polls={} stream-drops={}",
            producer.label(),
            mode.label(),
            count,
            stats.items,
            stats.host_calls,
            stats.pending_polls,
            stats.stream_drops,
        );
    }
    println!(
        "dynamic producer passed producer={} mode={} count={} items={:?} host-call-count={} pending-polls={} stream-drops={}",
        producer.label(),
        mode.label(),
        count,
        stats.items,
        stats.host_calls,
        stats.pending_polls,
        stats.stream_drops,
    );
    Ok(())
}

fn verify_cancel_run(
    stats: &Arc<Mutex<Stats>>,
    producer: ProducerShape,
    count: u64,
    value: u8,
) -> Result<()> {
    let stats = stats.lock().expect("dynamic producer cancellation stats mutex poisoned");
    let expected = vec![value; count as usize];
    if stats.items != expected
        || stats.host_calls != 1
        || stats.pending_polls != 0
        || stats.stream_drops != 1
    {
        bail!(
            "dynamic producer cancellation mismatch producer={} count={} items={:?} host-calls={} pending-polls={} stream-drops={}",
            producer.label(),
            count,
            stats.items,
            stats.host_calls,
            stats.pending_polls,
            stats.stream_drops,
        );
    }
    println!(
        "dynamic producer cancellation passed producer={} count={} items={:?} host-call-count={} pending-polls={} stream-drops=1 result=None",
        producer.label(),
        count,
        stats.items,
        stats.host_calls,
        stats.pending_polls,
    );
    Ok(())
}
