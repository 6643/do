use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{Component, Linker, Source, StreamConsumer, StreamReader, StreamResult};
use wasmtime::{Config, Engine, Store};

#[path = "../budget_gate.rs"]
mod budget_gate;

const CLI_STDOUT_INSTANCE: &str = "wasi:cli/stdout@0.3.0-rc-2025-09-16";
const STREAM_PROBE_SINK_INSTANCE: &str = "do:stream-probe/sink@0.1.0";
const STREAM_WRITER_FRAME_BYTES: u64 = 64;

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
    stream_dropped: bool,
}

struct RecordingConsumer {
    stats: Arc<Mutex<Stats>>,
    dropped: Option<oneshot::Sender<()>>,
    complete_until: Option<usize>,
    consumed_items: usize,
}

impl StreamConsumer<()> for RecordingConsumer {
    type Item = u8;

    fn poll_consume(
        self: Pin<&mut Self>,
        _: &mut TaskContext<'_>,
        mut store: wasmtime::StoreContextMut<'_, ()>,
        mut source: Source<'_, Self::Item>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let remaining = source.remaining(&mut store);
        if remaining == 0 {
            return Poll::Pending;
        }

        let mut items = Vec::with_capacity(remaining);
        source.read(&mut store, &mut items)?;
        let consumer = self.get_mut();
        consumer
            .stats
            .lock()
            .expect("CLI stdout stats mutex poisoned")
            .items
            .extend_from_slice(&items);
        consumer.consumed_items += items.len();
        let result = match consumer.complete_until {
            Some(limit) if consumer.consumed_items < limit => StreamResult::Completed,
            _ => StreamResult::Dropped,
        };
        Poll::Ready(Ok(result))
    }
}

impl Drop for RecordingConsumer {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("CLI stdout stats mutex poisoned")
            .stream_dropped = true;
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
        .context("usage: do-p3-cli-stream-stdout-host-runner <component.wasm>")?;
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
    let custom_variant = std::env::var("DO_STREAM_WRITER_VARIANT").as_deref() == Ok("custom");
    let wait_for_consumer = std::env::var_os("DO_STREAM_WRITER_CALLBACK_READY").is_none();
    let return_error = std::env::var_os("DO_STREAM_WRITER_ERROR").is_some();
    let scheduler_limit = std::env::var("DO_STREAM_WRITER_SCHEDULER_LIMIT")
        .ok()
        .map(|value| {
            value
                .parse::<u64>()
                .context("invalid CLI stdout scheduler limit")
        })
        .transpose()?;
    let budget_limit = std::env::var("DO_STREAM_WRITER_BUDGET_LIMIT")
        .ok()
        .map(|value| {
            value
                .parse::<i64>()
                .context("invalid CLI stdout budget limit")
        })
        .transpose()?;
    let expect_budget_rejection =
        std::env::var_os("DO_STREAM_WRITER_BUDGET_EXPECT_REJECT").is_some();
    let mut linker: Linker<()> = Linker::new(&engine);
    let sink_instance = if custom_variant {
        STREAM_PROBE_SINK_INSTANCE
    } else {
        CLI_STDOUT_INSTANCE
    };
    let mut stdout = map_wasmtime(linker.instance(sink_instance))?;
    let host_stats = Arc::clone(&stats);
    map_wasmtime(stdout.func_wrap_concurrent(
        "write-via-stream",
        move |accessor, (reader,): (StreamReader<u8>,)| {
            let consumer_stats = Arc::clone(&host_stats);
            let (dropped_sender, dropped_receiver) = oneshot::channel();
            let wait_for_consumer = wait_for_consumer;
            host_stats
                .lock()
                .expect("CLI stdout stats mutex poisoned")
                .host_calls += 1;
            Box::pin(async move {
                let pipe_result = accessor.with(|mut store| {
                    reader.pipe(
                        &mut store,
                        RecordingConsumer {
                            stats: consumer_stats,
                            dropped: Some(dropped_sender),
                            complete_until: custom_variant.then_some(2),
                            consumed_items: 0,
                        },
                    )
                });
                pipe_result?;
                if wait_for_consumer || custom_variant {
                    dropped_receiver.await.map_err(|_| {
                        wasmtime::Error::msg("stream consumer dropped before completion")
                    })?;
                }
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
    if custom_variant {
        let produce = map_wasmtime(
            instance
                .get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, "produce"),
        )?;
        let concurrent_result = store
            .run_concurrent(async |accessor| produce.call_concurrent(&accessor, ()).await)
            .await;
        if let Err(error) = &concurrent_result {
            return Err(anyhow::anyhow!("{error:#}"));
        }
        let result = map_wasmtime(map_wasmtime(concurrent_result)?)?;
        if return_error {
            if result.0 != Err(ErrorCode::Pipe) {
                bail!("expected custom producer Err(pipe), got {result:?}");
            }
            let stats = stats
                .lock()
                .expect("custom stream producer stats mutex poisoned");
            if stats.host_calls != 1 || !stats.stream_dropped {
                bail!(
                    "expected one custom producer error callback and stream drop, got host-calls={}, stream-dropped={}",
                    stats.host_calls,
                    stats.stream_dropped,
                );
            }
            println!(
                "Rust custom stream writer producer error passed result=err:pipe host-call-count=1 stream-dropped=true"
            );
            return Ok(());
        }
        if result.0 != Ok(()) {
            bail!("expected custom producer Ok(()), got {result:?}");
        }
        let stats = stats
            .lock()
            .expect("custom stream producer stats mutex poisoned");
        if !wait_for_consumer {
            if stats.host_calls != 1 {
                bail!(
                    "expected one immediate custom producer host call, got host-calls={}",
                    stats.host_calls
                );
            }
            println!(
                "Rust custom stream writer producer immediate passed result=ok host-call-count=1"
            );
            return Ok(());
        }
        if stats.items != [65, 66] || stats.host_calls != 1 || !stats.stream_dropped {
            bail!(
                "expected custom producer bytes [65, 66], one host call, and stream drop; got items={:?}, host-calls={}, stream-dropped={}",
                stats.items,
                stats.host_calls,
                stats.stream_dropped,
            );
        }
        println!(
            "Rust custom stream writer producer passed items=[65, 66] host-call-count=1 stream-dropped=true"
        );
        return Ok(());
    }
    let write = map_wasmtime(
        instance.get_typed_func::<(StreamReader<u8>,), (std::result::Result<(), ErrorCode>,)>(
            &mut store, "write",
        ),
    )?;

    if let Some(limit) = budget_limit {
        let configure = map_wasmtime(
            instance.get_typed_func::<(i64,), (i32,)>(&mut store, "byte-budget-limit"),
        )?;
        let configured = map_wasmtime(configure.call_async(&mut store, (limit,)).await)?;
        if configured.0 != 1 {
            bail!("CLI stdout budget configuration rejected limit={limit}");
        }
        let input = map_wasmtime(StreamReader::new(&mut store, vec![0x61, 0x62]))?;
        let outcome = store
            .run_concurrent(async |accessor| write.call_concurrent(&accessor, (input,)).await)
            .await;
        if expect_budget_rejection {
            match outcome {
                Ok(Ok(_)) => bail!(
                    "CLI stdout budget unexpectedly admitted frame={STREAM_WRITER_FRAME_BYTES} limit={limit}"
                ),
                Ok(Err(_)) | Err(_) => {
                    let host_calls = stats
                        .lock()
                        .expect("CLI stdout stats mutex poisoned")
                        .host_calls;
                    if host_calls != 0 {
                        bail!(
                            "CLI stdout budget rejection reached host callback limit={limit} host-calls={host_calls}"
                        );
                    }
                    println!(
                        "Rust CLI stdout budget adapter rejected limit={limit} frame={STREAM_WRITER_FRAME_BYTES} host-call-count=0"
                    );
                    return Ok(());
                }
            }
        }
        let result = map_wasmtime(map_wasmtime(outcome)?)?;
        if result.0 != Ok(()) {
            bail!("expected budgeted CLI stdout Ok(()), got {result:?}");
        }
        let host_calls = stats
            .lock()
            .expect("CLI stdout stats mutex poisoned")
            .host_calls;
        if host_calls != 1 {
            bail!("expected one budgeted CLI stdout host callback, got {host_calls}");
        }
        println!(
            "Rust CLI stdout budget adapter passed limit={limit} configured=1 frame={STREAM_WRITER_FRAME_BYTES} host-call-count=1"
        );
        return Ok(());
    }

    if let Some(limit) = scheduler_limit {
        let gate = budget_gate::BudgetGate::new(limit);
        let Some(first) = gate.try_acquire(STREAM_WRITER_FRAME_BYTES) else {
            let host_calls = stats
                .lock()
                .expect("CLI stdout stats mutex poisoned")
                .host_calls;
            println!(
                "Rust CLI stdout scheduler rejected before call limit={limit} frame={STREAM_WRITER_FRAME_BYTES} host-call-count={host_calls}"
            );
            return Ok(());
        };

        if gate.try_acquire(STREAM_WRITER_FRAME_BYTES).is_some() {
            bail!(
                "scheduler admitted a second frame before the first completed limit={limit} frame={STREAM_WRITER_FRAME_BYTES}"
            );
        }

        let first_input = map_wasmtime(StreamReader::new(&mut store, vec![0x61, 0x62]))?;
        let first_result = map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |accessor| {
                    write.call_concurrent(&accessor, (first_input,)).await
                })
                .await,
        )?)?;
        if first_result.0 != Ok(()) {
            bail!("expected first scheduled write Ok(()), got {first_result:?}");
        }
        if gate.used() != STREAM_WRITER_FRAME_BYTES {
            bail!(
                "scheduler permit released before first completion limit={limit} used={}",
                gate.used()
            );
        }
        drop(first);
        if gate.used() != 0 {
            bail!(
                "scheduler permit was not released after first completion limit={limit} used={}",
                gate.used()
            );
        }

        let second = gate
            .try_acquire(STREAM_WRITER_FRAME_BYTES)
            .ok_or_else(|| {
                anyhow::anyhow!(
                    "scheduler did not admit released frame limit={limit} frame={STREAM_WRITER_FRAME_BYTES}"
                )
            })?;
        let second_input = map_wasmtime(StreamReader::new(&mut store, vec![0x61, 0x62]))?;
        let second_result = map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |accessor| {
                    write.call_concurrent(&accessor, (second_input,)).await
                })
                .await,
        )?)?;
        if second_result.0 != Ok(()) {
            bail!("expected second scheduled write Ok(()), got {second_result:?}");
        }
        drop(second);
        if gate.used() != 0 {
            bail!(
                "scheduler permit was not released after second completion limit={limit} used={}",
                gate.used()
            );
        }

        let stats = stats.lock().expect("CLI stdout stats mutex poisoned");
        if stats.items != [0x61, 0x62, 0x61, 0x62] || stats.host_calls != 2 || !stats.stream_dropped
        {
            bail!(
                "expected two admitted writes and stream cleanup; got items={:?}, host-calls={}, stream-dropped={}",
                stats.items,
                stats.host_calls,
                stats.stream_dropped,
            );
        }
        println!(
            "Rust CLI stdout scheduler admission passed limit={limit} rejected=1 released=1 host-call-count={} items={:?}",
            stats.host_calls, stats.items,
        );
        return Ok(());
    }

    let input = map_wasmtime(StreamReader::new(&mut store, vec![0x61, 0x62]))?;
    let concurrent_result = store
        .run_concurrent(async |accessor| write.call_concurrent(&accessor, (input,)).await)
        .await;
    if let Err(error) = &concurrent_result {
        return Err(anyhow::anyhow!("{error:#}"));
    }
    let result = map_wasmtime(map_wasmtime(concurrent_result)?)?;
    if return_error {
        if result.0 != Err(ErrorCode::Pipe) {
            bail!("expected Err(pipe), got {result:?}");
        }
        let stats = stats.lock().expect("CLI stdout stats mutex poisoned");
        if stats.host_calls != 1 {
            bail!(
                "expected one error callback, got host-calls={}",
                stats.host_calls
            );
        }
        println!("Rust CLI stdout stream error callback passed result=err:pipe host-call-count=1");
        return Ok(());
    }
    if result.0 != Ok(()) {
        bail!("expected Ok(()), got {result:?}");
    }

    let stats = stats.lock().expect("CLI stdout stats mutex poisoned");
    if !wait_for_consumer {
        if stats.host_calls != 1 {
            bail!(
                "expected one immediate host call, got host-calls={}",
                stats.host_calls
            );
        }
        println!("Rust CLI stdout stream immediate callback passed result=ok host-call-count=1");
        return Ok(());
    }
    if stats.items != [0x61, 0x62] || stats.host_calls != 1 || !stats.stream_dropped {
        bail!(
            "expected stdout bytes [97, 98], one host call, and stream drop; got items={:?}, host-calls={}, stream-dropped={}",
            stats.items,
            stats.host_calls,
            stats.stream_dropped,
        );
    }
    println!(
        "Rust CLI stdout stream execution passed items=[97, 98] host-call-count=1 stream-dropped=true"
    );
    Ok(())
}
