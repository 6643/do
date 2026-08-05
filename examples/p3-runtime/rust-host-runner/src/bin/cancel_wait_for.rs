use anyhow::{Context, Result, bail};
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{Component, Linker};
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
    dropped_pending_future: u32,
}

struct PendingWait {
    stats: Arc<Mutex<Stats>>,
}

impl Future for PendingWait {
    type Output = wasmtime::Result<()>;

    fn poll(self: Pin<&mut Self>, _cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        let mut stats = self.stats.lock().expect("cancel stats mutex poisoned");
        stats.pending_polls += 1;
        Poll::Pending
    }
}

impl Drop for PendingWait {
    fn drop(&mut self) {
        let mut stats = self.stats.lock().expect("cancel stats mutex poisoned");
        stats.dropped_pending_future += 1;
    }
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-cancel-wait-for-host-runner <component.wasm>")?;
    futures::executor::block_on(run(Path::new(&component_path)))
}

async fn run(component_path: &Path) -> Result<()> {
    let immediate = std::env::var_os("DO_P3_CANCEL_IMMEDIATE").is_some();
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.wasm_gc(true);
    config.concurrency_support(true);

    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    let host_stats = Arc::clone(&stats);
    let mut clock = map_wasmtime(linker.instance(CLOCK_INSTANCE))?;
    map_wasmtime(
        clock.func_wrap_concurrent("wait-for", move |_accessor, (duration,): (u64,)| {
            let mut stats = host_stats.lock().expect("cancel stats mutex poisoned");
            stats.calls += 1;
            stats.duration = Some(duration);
            drop(stats);
            if immediate {
                return Box::pin(async move { Ok(()) });
            }
            Box::pin(PendingWait {
                stats: Arc::clone(&host_stats),
            })
        }),
    )?;

    let mut store = Store::new(&engine, ());
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(instance.get_typed_func::<(u64,), ()>(&mut store, "run"))?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| {
                run.call_concurrent(accessor, (EXPECTED_DURATION,)).await
            })
            .await,
    )?;
    map_wasmtime(call)?;

    let stats = stats.lock().expect("cancel stats mutex poisoned");
    if stats.duration != Some(EXPECTED_DURATION) || stats.calls != 1 {
        bail!(
            "expected one wait-for call with duration {EXPECTED_DURATION}, got calls={} duration={:?}",
            stats.calls,
            stats.duration
        );
    }
    let expected_dropped = if immediate { 0 } else { 1 };
    if stats.dropped_pending_future != expected_dropped {
        bail!(
            "expected the host future to be dropped {} times by cancellation, got {}",
            expected_dropped,
            stats.dropped_pending_future,
        );
    }

    println!(
        "Rust P3 cancel {} adapter passed",
        if immediate { "immediate" } else { "pending" }
    );
    println!("cancel before completion observed");
    println!("terminal subtask is not completed twice");
    println!("cancel pending-polls={}", stats.pending_polls);
    Ok(())
}
