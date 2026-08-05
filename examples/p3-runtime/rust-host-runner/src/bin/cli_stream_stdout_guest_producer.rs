use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use std::time::Duration;
use wasmtime::component::{Component, Linker, Source, StreamConsumer, StreamReader, StreamResult};
use wasmtime::{Config, Engine, Store};

#[path = "../budget_gate.rs"]
mod budget_gate;

const CLI_STDOUT_INSTANCE: &str = "wasi:cli/stdout@0.3.0-rc-2025-09-16";
const STREAM_WRITER_FRAME_BYTES: u64 = 64;

fn debug(message: &str) {
    if std::env::var_os("DO_DEBUG").is_some() {
        eprintln!("guest-producer: {message}");
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
enum ErrorCode {
    #[component(name = "io")]
    Io,
    #[component(name = "illegal-byte-sequence")]
    IllegalByteSequence,
    #[component(name = "pipe")]
    Pipe,
}

#[derive(Default)]
struct Stats {
    items: Vec<u8>,
    host_calls: u32,
    pending_writes: u32,
    writer_closed: u32,
    reader_drops: u32,
}

struct RecordingConsumer {
    stats: Arc<Mutex<Stats>>,
    dropped: Option<oneshot::Sender<()>>,
    pending_once: bool,
    drop_after_first: bool,
    consumed_items: usize,
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
        debug(if finish {
            "consumer finish"
        } else {
            "consumer poll"
        });
        if finish {
            return Poll::Ready(Ok(StreamResult::Dropped));
        }
        let remaining = source.remaining(&mut store);
        if std::env::var_os("DO_DEBUG").is_some() {
            eprintln!("guest-producer: consumer remaining={remaining}");
        }
        if remaining == 0 {
            return Poll::Pending;
        }

        let consumer = self.get_mut();
        if consumer.pending_once {
            consumer.pending_once = false;
            consumer
                .stats
                .lock()
                .expect("guest producer stats mutex poisoned")
                .pending_writes += 1;
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
        let consumed_items = consumer.consumed_items;
        {
            let mut stats = consumer
                .stats
                .lock()
                .expect("guest producer stats mutex poisoned");
            stats.items.extend_from_slice(&items);
        }
        if consumer.drop_after_first || consumed_items >= 3 {
            Poll::Ready(Ok(StreamResult::Dropped))
        } else {
            Poll::Ready(Ok(StreamResult::Completed))
        }
    }
}

impl Drop for RecordingConsumer {
    fn drop(&mut self) {
        debug("consumer drop");
        let mut stats = self
            .stats
            .lock()
            .expect("guest producer stats mutex poisoned");
        stats.reader_drops += 1;
        stats.writer_closed += 1;
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
        .context("usage: do-p3-cli-stream-stdout-guest-producer-host-runner <component.wasm>")?;
    futures::executor::block_on(run(Path::new(&component_path)))
}

async fn run(component_path: &Path) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);

    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let drop_after_first = std::env::var_os("DO_STREAM_WRITER_DROP_AFTER_FIRST").is_some();
    let return_error = std::env::var_os("DO_STREAM_WRITER_ERROR").is_some();
    let scheduler_limit = std::env::var("DO_STREAM_WRITER_SCHEDULER_LIMIT")
        .ok()
        .map(|value| {
            value
                .parse::<u64>()
                .context("invalid guest producer scheduler limit")
        })
        .transpose()?;
    let budget_limit = std::env::var("DO_STREAM_WRITER_BUDGET_LIMIT")
        .ok()
        .map(|value| {
            value
                .parse::<i64>()
                .context("invalid guest producer budget limit")
        })
        .transpose()?;
    let expect_budget_rejection =
        std::env::var_os("DO_STREAM_WRITER_BUDGET_EXPECT_REJECT").is_some();
    let mut linker: Linker<()> = Linker::new(&engine);
    let mut stdout = map_wasmtime(linker.instance(CLI_STDOUT_INSTANCE))?;
    let host_stats = Arc::clone(&stats);
    map_wasmtime(stdout.func_wrap_concurrent(
        "write-via-stream",
        move |accessor, (reader,): (StreamReader<u8>,)| {
            let consumer_stats = Arc::clone(&host_stats);
            let (dropped_sender, dropped_receiver) = oneshot::channel();
            host_stats
                .lock()
                .expect("guest producer stats mutex poisoned")
                .host_calls += 1;
            Box::pin(async move {
                debug("host callback body start");
                accessor.with(|mut store| {
                    reader.pipe(
                        &mut store,
                        RecordingConsumer {
                            stats: consumer_stats,
                            dropped: Some(dropped_sender),
                            pending_once: true,
                            drop_after_first,
                            consumed_items: 0,
                        },
                    )
                })?;
                debug("host callback pipe installed");
                dropped_receiver
                    .await
                    .map_err(|_| wasmtime::Error::msg("stream reader was not dropped"))?;
                debug("host callback reader dropped");
                let result = if return_error {
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
    let produce = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, "produce"),
    )?;

    if let Some(limit) = budget_limit {
        let configure = map_wasmtime(
            instance.get_typed_func::<(i64,), (i32,)>(&mut store, "byte-budget-limit"),
        )?;
        let configured = map_wasmtime(configure.call_async(&mut store, (limit,)).await)?;
        if configured.0 != 1 {
            bail!("guest producer budget configuration rejected limit={limit}");
        }
        let outcome = store
            .run_concurrent(async |accessor| produce.call_concurrent(&accessor, ()).await)
            .await;
        if expect_budget_rejection {
            match outcome {
                Ok(Ok(_)) => bail!(
                    "guest producer budget unexpectedly admitted frame={STREAM_WRITER_FRAME_BYTES} limit={limit}"
                ),
                Ok(Err(_)) | Err(_) => {
                    let host_calls = stats
                        .lock()
                        .expect("guest producer stats mutex poisoned")
                        .host_calls;
                    if host_calls != 0 {
                        bail!(
                            "guest producer budget rejection reached host callback limit={limit} host-calls={host_calls}"
                        );
                    }
                    println!(
                        "Rust guest producer budget adapter rejected limit={limit} frame={STREAM_WRITER_FRAME_BYTES} host-call-count=0"
                    );
                    return Ok(());
                }
            }
        }
        let result = map_wasmtime(map_wasmtime(outcome)?)?;
        if result.0 != Ok(()) {
            bail!("expected budgeted guest producer Ok(()), got {result:?}");
        }
        let host_calls = stats
            .lock()
            .expect("guest producer stats mutex poisoned")
            .host_calls;
        if host_calls != 1 {
            bail!("expected one budgeted guest producer host callback, got {host_calls}");
        }
        println!(
            "Rust guest producer budget adapter passed limit={limit} configured=1 frame={STREAM_WRITER_FRAME_BYTES} host-call-count=1"
        );
        return Ok(());
    }

    if let Some(limit) = scheduler_limit {
        let gate = budget_gate::BudgetGate::new(limit);
        let Some(first) = gate.try_acquire(STREAM_WRITER_FRAME_BYTES) else {
            let host_calls = stats
                .lock()
                .expect("guest producer stats mutex poisoned")
                .host_calls;
            println!(
                "Rust guest producer scheduler rejected before call limit={limit} frame={STREAM_WRITER_FRAME_BYTES} host-call-count={host_calls}"
            );
            return Ok(());
        };
        if gate.try_acquire(STREAM_WRITER_FRAME_BYTES).is_some() {
            bail!(
                "scheduler admitted a second guest producer frame before the first completed limit={limit} frame={STREAM_WRITER_FRAME_BYTES}"
            );
        }

        let first_result = map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |accessor| produce.call_concurrent(&accessor, ()).await)
                .await,
        )?)?;
        if first_result.0 != Ok(()) {
            bail!("expected first scheduled guest producer Ok(()), got {first_result:?}");
        }
        if gate.used() != STREAM_WRITER_FRAME_BYTES {
            bail!(
                "guest producer scheduler permit released before first completion limit={limit} used={}",
                gate.used()
            );
        }
        drop(first);
        if gate.used() != 0 {
            bail!(
                "guest producer scheduler permit was not released after first completion limit={limit} used={}",
                gate.used()
            );
        }

        let second = gate.try_acquire(STREAM_WRITER_FRAME_BYTES).ok_or_else(|| {
            anyhow::anyhow!("guest producer scheduler did not admit released frame")
        })?;
        let second_result = map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |accessor| produce.call_concurrent(&accessor, ()).await)
                .await,
        )?)?;
        if second_result.0 != Ok(()) {
            bail!("expected second scheduled guest producer Ok(()), got {second_result:?}");
        }
        drop(second);
        if gate.used() != 0 {
            bail!(
                "guest producer scheduler permit was not released after second completion limit={limit} used={}",
                gate.used()
            );
        }

        let stats = stats.lock().expect("guest producer stats mutex poisoned");
        if stats.items != [65, 66, 67, 65, 66, 67]
            || stats.host_calls != 2
            || stats.pending_writes != 2
            || stats.writer_closed != 2
            || stats.reader_drops != 2
        {
            bail!(
                "expected two admitted guest producer writes and cleanup; got items={:?}, host-calls={}, pending-writes={}, writer-closed={}, reader-drops={}",
                stats.items,
                stats.host_calls,
                stats.pending_writes,
                stats.writer_closed,
                stats.reader_drops,
            );
        }
        println!(
            "Rust guest producer scheduler admission passed limit={limit} rejected=1 released=1 host-call-count={} items={:?}",
            stats.host_calls, stats.items,
        );
        return Ok(());
    }

    let result = map_wasmtime(map_wasmtime({
        debug("calling produce");
        store
            .run_concurrent(async |accessor| produce.call_concurrent(&accessor, ()).await)
            .await
    })?)?;
    debug("produce returned");
    if return_error {
        if result.0 != Err(ErrorCode::Pipe) {
            bail!("expected Err(pipe), got {result:?}");
        }
        let stats = stats.lock().expect("guest producer stats mutex poisoned");
        if stats.items != [65, 66, 67]
            || stats.host_calls != 1
            || stats.pending_writes != 1
            || stats.writer_closed != 1
            || stats.reader_drops != 1
        {
            bail!(
                "expected host error after three bytes and one pending write; got items={:?}, host-calls={}, pending-writes={}, writer-closed={}, reader-drops={}",
                stats.items,
                stats.host_calls,
                stats.pending_writes,
                stats.writer_closed,
                stats.reader_drops,
            );
        }
        println!(
            "Rust guest producer host error passed result=err:pipe items=[65, 66, 67] host-call-count=1 pending-writes=1 writer-closed=true reader-drops=1"
        );
        return Ok(());
    }
    if result.0 != Ok(()) {
        bail!("expected Ok(()), got {result:?}");
    }

    let stats = stats.lock().expect("guest producer stats mutex poisoned");
    if drop_after_first {
        if stats.items != [65]
            || stats.host_calls != 1
            || stats.pending_writes != 1
            || stats.writer_closed != 1
            || stats.reader_drops != 1
        {
            bail!(
                "expected early reader drop after one byte and one pending write; got items={:?}, host-calls={}, pending-writes={}, writer-closed={}, reader-drops={}",
                stats.items,
                stats.host_calls,
                stats.pending_writes,
                stats.writer_closed,
                stats.reader_drops,
            );
        }
        println!(
            "Rust guest producer early reader drop passed items=[65] host-call-count=1 pending-writes=1 writer-closed=true reader-drops=1"
        );
        return Ok(());
    }
    if stats.items != [65, 66, 67]
        || stats.host_calls != 1
        || stats.pending_writes != 1
        || stats.writer_closed != 1
        || stats.reader_drops != 1
    {
        bail!(
            "expected three bytes, one pending write, one host call, writer close, and reader drop; got items={:?}, host-calls={}, pending-writes={}, writer-closed={}, reader-drops={}",
            stats.items,
            stats.host_calls,
            stats.pending_writes,
            stats.writer_closed,
            stats.reader_drops,
        );
    }

    println!(
        "Rust guest producer stream execution passed items=[65, 66, 67] host-call-count=1 pending-writes=1 writer-closed=true reader-drops=1"
    );
    Ok(())
}
