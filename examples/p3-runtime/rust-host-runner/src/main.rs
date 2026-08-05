use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{Accessor, AccessorTask, Component, Linker};
use wasmtime::{Config, Engine, Store};

const EXPECTED_DURATION: u64 = 27_815;
const CLOCK_INSTANCE: &str = "wasi:clocks/monotonic-clock@0.3.0";

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error}"))
}

#[derive(Default)]
struct Stats {
    duration: Option<u64>,
    calls: u32,
    pending_polls: u32,
    external_wakes: u32,
    completions: u32,
}

struct WaitFor {
    stats: Arc<Mutex<Stats>>,
    completion: oneshot::Receiver<()>,
    pending_recorded: bool,
}

impl Future for WaitFor {
    type Output = wasmtime::Result<()>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        match Pin::new(&mut self.completion).poll(cx) {
            Poll::Pending => {
                if self.pending_recorded {
                    return Poll::Pending;
                }
                self.pending_recorded = true;
                let mut stats = self.stats.lock().expect("wait-for stats mutex poisoned");
                stats.pending_polls += 1;
                Poll::Pending
            }
            Poll::Ready(Ok(())) => {
                let mut stats = self.stats.lock().expect("wait-for stats mutex poisoned");
                stats.completions += 1;
                Poll::Ready(Ok(()))
            }
            Poll::Ready(Err(_)) => {
                Poll::Ready(Err(wasmtime::Error::msg("wait-for host event dropped")))
            }
        }
    }
}

struct HostWake {
    stats: Arc<Mutex<Stats>>,
    completion: oneshot::Sender<()>,
}

impl AccessorTask<()> for HostWake {
    fn run(self, _accessor: &Accessor<()>) -> impl Future<Output = wasmtime::Result<()>> + Send {
        async move {
            let mut stats = self.stats.lock().expect("wait-for stats mutex poisoned");
            stats.external_wakes += 1;
            drop(stats);
            let _ = self.completion.send(());
            Ok(())
        }
    }
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-wait-for-host-runner <component.wat>")?;
    let expected_duration = std::env::var("DO_P3_CLOCK_EXPECTED_DURATION")
        .ok()
        .map(|value| value.parse::<u64>())
        .transpose()
        .context("DO_P3_CLOCK_EXPECTED_DURATION must be an unsigned integer")?
        .unwrap_or(EXPECTED_DURATION);
    let input_duration = std::env::var("DO_P3_CLOCK_INPUT")
        .ok()
        .map(|value| value.parse::<u64>())
        .transpose()
        .context("DO_P3_CLOCK_INPUT must be an unsigned integer")?
        .unwrap_or(expected_duration);
    futures::executor::block_on(run(
        Path::new(&component_path),
        input_duration,
        expected_duration,
    ))
}

async fn run(component_path: &Path, input_duration: u64, expected_duration: u64) -> Result<()> {
    let immediate = std::env::var_os("DO_P3_CLOCK_IMMEDIATE").is_some();
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
    let host_stats = Arc::clone(&stats);
    let mut clock = map_wasmtime(linker.instance(CLOCK_INSTANCE))?;
    map_wasmtime(
        clock.func_wrap_concurrent("wait-for", move |accessor, (duration,): (u64,)| {
            let mut stats = host_stats.lock().expect("wait-for stats mutex poisoned");
            stats.calls += 1;
            stats.duration = Some(duration);
            drop(stats);
            if immediate {
                return Box::pin(async move { Ok(()) });
            }
            let (completion_sender, completion) = oneshot::channel();
            let host_event = accessor.spawn(HostWake {
                stats: Arc::clone(&host_stats),
                completion: completion_sender,
            });
            let wait_for = WaitFor {
                stats: Arc::clone(&host_stats),
                completion,
                pending_recorded: false,
            };
            Box::pin(async move {
                host_event?;
                wait_for.await
            })
        }),
    )?;
    let host_stats = Arc::clone(&stats);
    map_wasmtime(
        clock.func_wrap_concurrent("wait-until", move |accessor, (when,): (u64,)| {
            let mut stats = host_stats.lock().expect("wait-until stats mutex poisoned");
            stats.calls += 1;
            stats.duration = Some(when);
            drop(stats);
            if immediate {
                return Box::pin(async move { Ok(()) });
            }
            let (completion_sender, completion) = oneshot::channel();
            let host_event = accessor.spawn(HostWake {
                stats: Arc::clone(&host_stats),
                completion: completion_sender,
            });
            let wait_until = WaitFor {
                stats: Arc::clone(&host_stats),
                completion,
                pending_recorded: false,
            };
            Box::pin(async move {
                host_event?;
                wait_until.await
            })
        }),
    )?;

    let mut store = Store::new(&engine, ());
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(instance.get_typed_func::<(u64,), ()>(&mut store, "run"))?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(accessor, (input_duration,)).await)
            .await,
    )?;
    map_wasmtime(call)?;

    let stats = stats.lock().expect("wait-for stats mutex poisoned");
    if stats.duration != Some(expected_duration) {
        bail!(
            "expected wait-for duration {expected_duration}, got {:?}",
            stats.duration,
        );
    }
    let expected_async_stats = if immediate { (0, 0, 0) } else { (1, 1, 1) };
    if stats.calls != 1
        || (stats.pending_polls, stats.external_wakes, stats.completions) != expected_async_stats
    {
        bail!(
            "expected clock stats {:?}; got calls={}, pending-polls={}, external-wakes={}, completions={}",
            expected_async_stats,
            stats.calls,
            stats.pending_polls,
            stats.external_wakes,
            stats.completions
        );
    }

    println!(
        "Rust P3 clocks {} adapter passed",
        if immediate { "immediate" } else { "pending" }
    );
    println!("clock argument={expected_duration}");
    println!("clock pending-polls={}", stats.pending_polls);
    println!("clock external-wakes={}", stats.external_wakes);
    println!("clock completions={}", stats.completions);
    Ok(())
}
