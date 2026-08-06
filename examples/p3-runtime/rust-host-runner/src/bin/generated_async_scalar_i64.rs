use anyhow::{Context, Result, bail};
use std::future::Future as StdFuture;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{Component, FutureReader, Linker, ResourceTable};
use wasmtime::{Config, Engine, Store};

const HOST_INSTANCE: &str = "do:generic-async-scalar-i64-probe/host@0.1.0";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Ready,
    Pending,
    Cancel,
}

impl Mode {
    fn from_environment() -> Result<Self> {
        match std::env::var("DO_GENERIC_ASYNC_SCALAR_MODE")
            .unwrap_or_else(|_| "ready".to_owned())
            .as_str()
        {
            "ready" => Ok(Self::Ready),
            "pending" => Ok(Self::Pending),
            "cancel" => Ok(Self::Cancel),
            value => bail!("DO_GENERIC_ASYNC_SCALAR_MODE must be ready, pending, or cancel, got {value}"),
        }
    }
}

#[derive(Default)]
struct Stats {
    host_calls: u32,
    polls: u32,
    wakes: u32,
    completions: u32,
    future_drops: u32,
    pending_future_drops: u32,
}

#[derive(Clone, Copy)]
enum FuturePlan {
    Ready,
    PendingOnce,
    PendingForever,
}

struct ScalarCompletion {
    stats: Arc<Mutex<Stats>>,
    plan: FuturePlan,
    completed: bool,
    polled: bool,
}

impl StdFuture for ScalarCompletion {
    type Output = wasmtime::Result<i64>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        if self.completed {
            panic!("scalar i64 completion polled after terminal completion");
        }
        {
            let mut stats = self.stats.lock().expect("scalar i64 stats mutex poisoned");
            stats.polls += 1;
        }
        if matches!(self.plan, FuturePlan::PendingForever) {
            return Poll::Pending;
        }
        if matches!(self.plan, FuturePlan::PendingOnce) && !self.polled {
            self.polled = true;
            let mut stats = self.stats.lock().expect("scalar i64 stats mutex poisoned");
            stats.wakes += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        self.polled = true;
        self.completed = true;
        let mut stats = self.stats.lock().expect("scalar i64 stats mutex poisoned");
        stats.completions += 1;
        Poll::Ready(Ok(42))
    }
}

impl Drop for ScalarCompletion {
    fn drop(&mut self) {
        let mut stats = self.stats.lock().expect("scalar i64 stats mutex poisoned");
        stats.future_drops += 1;
        if !self.completed {
            stats.pending_future_drops += 1;
        }
    }
}

struct State {
    table: ResourceTable,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn plan_for(mode: Mode, call: u32) -> FuturePlan {
    match mode {
        Mode::Ready => FuturePlan::Ready,
        Mode::Pending if call == 1 => FuturePlan::PendingOnce,
        Mode::Pending => FuturePlan::Ready,
        Mode::Cancel if call == 1 => FuturePlan::Ready,
        Mode::Cancel => FuturePlan::PendingForever,
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
    let mut host = map_wasmtime(linker.instance(HOST_INSTANCE))?;
    let host_stats = Arc::clone(&stats);
    map_wasmtime(host.func_wrap("completion", move |mut store, ()| {
        let call = {
            let mut stats = host_stats.lock().expect("scalar i64 stats mutex poisoned");
            stats.host_calls += 1;
            stats.host_calls
        };
        let plan = plan_for(mode, call);
        Ok((FutureReader::new(
            &mut store,
            ScalarCompletion {
                stats: Arc::clone(&host_stats),
                plan,
                completed: false,
                polled: false,
            },
        )?,))
    }))?;

    let mut store = Store::new(&engine, State { table: ResourceTable::new() });
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, "run"))?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    map_wasmtime(call)?;

    let stats = stats.lock().expect("scalar i64 stats mutex poisoned");
    if stats.host_calls != 2
        || stats.completions != if mode == Mode::Cancel { 1 } else { 2 }
        || stats.future_drops != 2
        || stats.pending_future_drops != u32::from(mode == Mode::Cancel)
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected scalar i64 stats: host-calls={} polls={} wakes={} completions={} future-drops={} pending-future-drops={} table-empty={}",
            stats.host_calls,
            stats.polls,
            stats.wakes,
            stats.completions,
            stats.future_drops,
            stats.pending_future_drops,
            store.data().table.is_empty(),
        );
    }
    if mode == Mode::Pending && (stats.polls != 3 || stats.wakes != 1) {
        bail!("pending scalar i64 ABI mismatch: polls={} wakes={}", stats.polls, stats.wakes);
    }
    if mode == Mode::Ready && (stats.polls != 2 || stats.wakes != 0) {
        bail!("ready scalar i64 ABI mismatch: polls={} wakes={}", stats.polls, stats.wakes);
    }
    println!(
        "mode={} value=42 polls={} wakes={} completions={} future-drops={} pending-future-drops={} frame-drops=1 table-empty=true",
        match mode {
            Mode::Ready => "ready",
            Mode::Pending => "pending",
            Mode::Cancel => "cancel",
        },
        stats.polls,
        stats.wakes,
        stats.completions,
        stats.future_drops,
        stats.pending_future_drops,
    );
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-generated-async-scalar-i64-host-runner <component.wasm>")?;
    let mode = Mode::from_environment()?;
    futures::executor::block_on(run(Path::new(&component_path), mode))
}
