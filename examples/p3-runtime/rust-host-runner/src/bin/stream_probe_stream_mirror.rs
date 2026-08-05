use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use futures::future::{Either, select};
use futures::pin_mut;
use std::future::Future;
use std::mem;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use std::thread;
use std::time::Duration;
use wasmtime::component::{
    Component, Destination, FutureReader, Linker, ResourceTable, Source, StreamConsumer,
    StreamProducer, StreamReader, StreamResult, VecBuffer,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const SOURCE_INSTANCE: &str = "do:stream-probe/source@0.1.0";
const SINK_INSTANCE: &str = "do:stream-probe/sink@0.1.0";

fn debug(message: &str) {
    if std::env::var_os("DO_DEBUG").is_some() {
        eprintln!("stream-mirror: {message}");
    }
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
    #[component(name = "illegal-byte-sequence")]
    IllegalByteSequence,
    #[component(name = "pipe")]
    Pipe,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Mode {
    Pending,
    Ready,
    SourceEof,
    Error,
    Cancel,
    EarlyDrop,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "pending" => Ok(Self::Pending),
            "ready" => Ok(Self::Ready),
            "source-eof" => Ok(Self::SourceEof),
            "error" => Ok(Self::Error),
            "cancel" => Ok(Self::Cancel),
            "early-drop" => Ok(Self::EarlyDrop),
            other => bail!(
                "unknown mode {other}; expected pending, ready, source-eof, error, cancel, or early-drop"
            ),
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Ready => "ready",
            Self::SourceEof => "source-eof",
            Self::Error => "error",
            Self::Cancel => "cancel",
            Self::EarlyDrop => "early-drop",
        }
    }
}

#[derive(Default)]
struct Stats {
    items: Vec<u8>,
    source_stream_drops: u32,
    source_future_drops: u32,
    source_completion_polls: u32,
    sink_callbacks: u32,
    sink_stream_drops: u32,
    sink_pending_polls: u32,
}

struct State {
    table: ResourceTable,
}

struct RecordingSource {
    stats: Arc<Mutex<Stats>>,
    items: Vec<u8>,
}

impl Drop for RecordingSource {
    fn drop(&mut self) {
        debug("source producer drop");
        self.stats
            .lock()
            .expect("stream mirror stats mutex poisoned")
            .source_stream_drops += 1;
    }
}

impl StreamProducer<State> for RecordingSource {
    type Item = u8;
    type Buffer = VecBuffer<u8>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _: &mut TaskContext<'_>,
        _: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        debug(if finish {
            "source producer poll finish"
        } else {
            "source producer poll"
        });
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let source = self.get_mut();
        let items = mem::take(&mut source.items);
        debug(&format!("source producer supplied {} items", items.len()));
        destination.set_buffer(items.into());
        Poll::Ready(Ok(StreamResult::Dropped))
    }
}

struct RecordingCompletion {
    stats: Arc<Mutex<Stats>>,
}

impl Drop for RecordingCompletion {
    fn drop(&mut self) {
        debug("source completion drop");
        self.stats
            .lock()
            .expect("stream mirror stats mutex poisoned")
            .source_future_drops += 1;
    }
}

impl Future for RecordingCompletion {
    type Output = wasmtime::Result<std::result::Result<(), ErrorCode>>;

    fn poll(self: Pin<&mut Self>, _: &mut TaskContext<'_>) -> Poll<Self::Output> {
        debug("source completion poll");
        self.stats
            .lock()
            .expect("stream mirror stats mutex poisoned")
            .source_completion_polls += 1;
        Poll::Pending
    }
}

struct RecordingSink {
    stats: Arc<Mutex<Stats>>,
    dropped: Option<oneshot::Sender<()>>,
    pending_once: bool,
    early_drop: bool,
    consumed_items: usize,
}

impl StreamConsumer<State> for RecordingSink {
    type Item = u8;

    fn poll_consume(
        self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        mut store: wasmtime::StoreContextMut<'_, State>,
        mut source: Source<'_, Self::Item>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        debug(if finish {
            "sink consumer poll finish"
        } else {
            "sink consumer poll"
        });
        if finish {
            return Poll::Ready(Ok(StreamResult::Dropped));
        }

        let sink = self.get_mut();
        let remaining = source.remaining(&mut store);
        debug(&format!("sink consumer remaining={remaining}"));
        if remaining == 0 {
            return Poll::Pending;
        }
        if sink.pending_once {
            sink.pending_once = false;
            sink.stats
                .lock()
                .expect("stream mirror stats mutex poisoned")
                .sink_pending_polls += 1;
            let waker = cx.waker().clone();
            thread::spawn(move || {
                thread::sleep(Duration::from_millis(5));
                waker.wake();
            });
            return Poll::Pending;
        }

        let mut items = Vec::with_capacity(remaining);
        source.read(&mut store, &mut items)?;
        sink.consumed_items += items.len();
        sink.stats
            .lock()
            .expect("stream mirror stats mutex poisoned")
            .items
            .extend_from_slice(&items);
        if sink.early_drop {
            Poll::Ready(Ok(StreamResult::Dropped))
        } else {
            Poll::Ready(Ok(StreamResult::Completed))
        }
    }
}

impl Drop for RecordingSink {
    fn drop(&mut self) {
        debug("sink consumer drop");
        let mut stats = self
            .stats
            .lock()
            .expect("stream mirror stats mutex poisoned");
        stats.sink_stream_drops += 1;
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
        .context("usage: do-p3-stream-mirror-host-runner <component.wasm> [pending|ready|source-eof|error|cancel|early-drop]")?;
    let mode = Mode::parse(
        &std::env::args()
            .nth(2)
            .unwrap_or_else(|| "pending".to_string()),
    )?;
    futures::executor::block_on(run(Path::new(&component_path), mode))
}

fn install_source(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: Mode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_INSTANCE)?;
    let source_stats = Arc::clone(&stats);
    source.func_wrap("read-via-stream", move |mut store, ()| {
        debug("source read-via-stream callback start");
        let items = if mode == Mode::SourceEof {
            vec![65, 66]
        } else {
            vec![65, 66, 67]
        };
        let reader = StreamReader::new(
            &mut store,
            RecordingSource {
                stats: Arc::clone(&source_stats),
                items,
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            RecordingCompletion {
                stats: Arc::clone(&source_stats),
            },
        )?;
        debug("source read-via-stream callback returned handles");
        Ok(((reader, completion),))
    })?;
    Ok(())
}

fn cancellation_delay() -> impl Future<Output = ()> {
    async {
        let (sender, receiver) = oneshot::channel();
        thread::spawn(move || {
            thread::sleep(Duration::from_millis(25));
            let _ = sender.send(());
        });
        let _ = receiver.await;
    }
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
    map_wasmtime(install_source(&mut linker, Arc::clone(&stats), mode))?;

    let sink_stats = Arc::clone(&stats);
    let mut sink = map_wasmtime(linker.instance(SINK_INSTANCE))?;
    map_wasmtime(sink.func_wrap_concurrent(
        "write-via-stream",
        move |accessor, (reader,): (StreamReader<u8>,)| {
            debug("sink write-via-stream callback start");
            let stats = Arc::clone(&sink_stats);
            let (dropped_sender, dropped_receiver) = oneshot::channel();
            stats
                .lock()
                .expect("stream mirror stats mutex poisoned")
                .sink_callbacks += 1;
            Box::pin(async move {
                accessor.with(|mut store| {
                    debug("sink installing stream consumer");
                    reader.pipe(
                        &mut store,
                        RecordingSink {
                            stats: Arc::clone(&stats),
                            dropped: Some(dropped_sender),
                            pending_once: mode == Mode::Pending,
                            early_drop: mode == Mode::EarlyDrop,
                            consumed_items: 0,
                        },
                    )
                })?;
                debug("sink stream consumer installed");
                dropped_receiver.await.map_err(|_| {
                    wasmtime::Error::msg("stream mirror sink reader was not dropped")
                })?;
                debug("sink stream reader dropped");
                if mode == Mode::Cancel {
                    futures::future::pending::<()>().await;
                }
                let result = if mode == Mode::Error {
                    Err(ErrorCode::Pipe)
                } else {
                    Ok(())
                };
                debug("sink write-via-stream callback returning result");
                Ok::<(std::result::Result<(), ErrorCode>,), wasmtime::Error>((result,))
            })
        },
    ))?;

    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let produce = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, "produce"),
    )?;

    if mode == Mode::Cancel {
        {
            let call =
                store.run_concurrent(async |accessor| produce.call_concurrent(&accessor, ()).await);
            pin_mut!(call);
            let delay = cancellation_delay();
            pin_mut!(delay);
            match select(call, delay).await {
                Either::Left((result, _)) => {
                    let result = map_wasmtime(map_wasmtime(result)?)?;
                    bail!("cancel mode completed before cancellation: {result:?}");
                }
                Either::Right((_, remaining_call)) => drop(remaining_call),
            }
        }
        thread::sleep(Duration::from_millis(25));
        verify_cancel(&stats, &store.data().table)?;
        println!("stream mirror passed mode=cancel source-future-drop=1 table-empty=true");
        return Ok(());
    }

    debug("produce call start");
    let call = store
        .run_concurrent(async |accessor| produce.call_concurrent(&accessor, ()).await)
        .await;
    debug("produce call returned");
    let call = map_wasmtime(call)?;
    let result = map_wasmtime(call)?;
    debug("produce result lifted");
    verify_mode(&stats, mode, result, &store.data().table)?;
    Ok(())
}

fn verify_cancel(stats: &Arc<Mutex<Stats>>, table: &ResourceTable) -> Result<()> {
    let stats = stats.lock().expect("stream mirror stats mutex poisoned");
    if stats.source_completion_polls != 0
        || stats.source_stream_drops != 1
        || stats.source_future_drops != 1
        || stats.sink_callbacks != 1
        || stats.sink_stream_drops != 1
        || !table.is_empty()
    {
        bail!(
            "cancel cleanup mismatch items={:?} source-stream-drops={} source-future-drops={} completion-polls={} sink-callbacks={} sink-stream-drops={} table-empty={}",
            stats.items,
            stats.source_stream_drops,
            stats.source_future_drops,
            stats.source_completion_polls,
            stats.sink_callbacks,
            stats.sink_stream_drops,
            table.is_empty(),
        );
    }
    Ok(())
}

fn verify_mode(
    stats: &Arc<Mutex<Stats>>,
    mode: Mode,
    result: (std::result::Result<(), ErrorCode>,),
    table: &ResourceTable,
) -> Result<()> {
    let stats = stats.lock().expect("stream mirror stats mutex poisoned");
    let expected_items: &[u8] = match mode {
        Mode::SourceEof => &[65, 66],
        Mode::EarlyDrop => &[65],
        _ => &[65, 66, 67],
    };
    let expected_result = if mode == Mode::Error {
        Err(ErrorCode::Pipe)
    } else {
        Ok(())
    };
    let expected_pending = if mode == Mode::Pending { 1 } else { 0 };
    if result.0 != expected_result
        || stats.items != expected_items
        || stats.source_stream_drops != 1
        || stats.source_future_drops != 1
        || stats.source_completion_polls != 0
        || stats.sink_callbacks != 1
        || stats.sink_stream_drops != 1
        || stats.sink_pending_polls != expected_pending
        || !table.is_empty()
    {
        bail!(
            "stream mirror mismatch mode={} result={result:?} items={:?} source-stream-drops={} source-future-drops={} completion-polls={} sink-callbacks={} sink-stream-drops={} sink-pending-polls={} table-empty={}",
            mode.label(),
            stats.items,
            stats.source_stream_drops,
            stats.source_future_drops,
            stats.source_completion_polls,
            stats.sink_callbacks,
            stats.sink_stream_drops,
            stats.sink_pending_polls,
            table.is_empty(),
        );
    }
    println!(
        "stream mirror passed mode={} items={:?} source-stream-drops=1 source-future-drops=1 sink-callbacks=1 sink-stream-drops=1 sink-pending-polls={} table-empty=true result={}",
        mode.label(),
        stats.items,
        stats.sink_pending_polls,
        if mode == Mode::Error {
            "err:pipe"
        } else {
            "ok"
        },
    );
    Ok(())
}
