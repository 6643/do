use anyhow::{Context, Result, bail};
use futures::future::{Either, select};
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{Component, Linker, ResourceTable, Val};
use wasmtime::{Config, Engine, Store};

const API_INSTANCE: &str = "demo:map-async-probe/api@0.1.0";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Ready,
    Pending,
    Cancel,
    Drop,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "ready" => Ok(Self::Ready),
            "pending" => Ok(Self::Pending),
            "cancel" => Ok(Self::Cancel),
            "drop" => Ok(Self::Drop),
            other => bail!("mode must be ready, pending, cancel, or drop (got {other})"),
        }
    }

    fn is_cancelled(self) -> bool {
        matches!(self, Self::Cancel | Self::Drop)
    }
}

#[derive(Default)]
struct Stats {
    host_calls: AtomicU32,
    input_mismatches: AtomicU32,
    polls: AtomicU32,
    wakes: AtomicU32,
    completions: AtomicU32,
    future_drops: AtomicU32,
    pending_future_drops: AtomicU32,
    guest_cancelled: AtomicBool,
}

#[derive(Clone, Copy)]
enum FuturePlan {
    Ready,
    PendingOnce,
    PendingForever,
}

struct MapCompletion {
    stats: Arc<Stats>,
    plan: FuturePlan,
    polled: bool,
    completed: bool,
}

impl Future for MapCompletion {
    type Output = wasmtime::Result<()>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        self.stats.polls.fetch_add(1, Ordering::SeqCst);
        match self.plan {
            FuturePlan::Ready => {}
            FuturePlan::PendingOnce if !self.polled => {
                self.polled = true;
                self.stats.wakes.fetch_add(1, Ordering::SeqCst);
                cx.waker().wake_by_ref();
                return Poll::Pending;
            }
            FuturePlan::PendingForever => return Poll::Pending,
            FuturePlan::PendingOnce => {}
        }
        self.polled = true;
        self.completed = true;
        self.stats.completions.fetch_add(1, Ordering::SeqCst);
        Poll::Ready(Ok(()))
    }
}

impl Drop for MapCompletion {
    fn drop(&mut self) {
        self.stats.future_drops.fetch_add(1, Ordering::SeqCst);
        if !self.completed {
            self.stats
                .pending_future_drops
                .fetch_add(1, Ordering::SeqCst);
        }
    }
}

struct CancelAfterHostCall {
    stats: Arc<Stats>,
}

impl Future for CancelAfterHostCall {
    type Output = ();

    fn poll(self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        if self.stats.host_calls.load(Ordering::SeqCst) >= 1 {
            Poll::Ready(())
        } else {
            cx.waker().wake_by_ref();
            Poll::Pending
        }
    }
}

struct State {
    table: ResourceTable,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn plan_for(mode: Mode) -> FuturePlan {
    match mode {
        Mode::Ready => FuturePlan::Ready,
        Mode::Pending => FuturePlan::PendingOnce,
        Mode::Cancel | Mode::Drop => FuturePlan::PendingForever,
    }
}

async fn run(component_path: &Path, mode: Mode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.wasm_component_model_map(true);
    config.wasm_gc(true);
    config.concurrency_support(true);

    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let stats = Arc::new(Stats::default());
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut api = map_wasmtime(linker.instance(API_INSTANCE))?;
    let host_stats = Arc::clone(&stats);
    map_wasmtime(
        api.func_new_concurrent("submit", move |_accessor, _ty, params, results| {
            let entries = match params.first() {
                Some(Val::Map(values)) => values
                    .iter()
                    .map(|(key, value)| match (key, value) {
                        (Val::U32(key), Val::U32(value)) => Ok((*key, *value)),
                        other => Err(wasmtime::Error::msg(format!(
                            "async map entry was not u32/u32: {other:?}"
                        ))),
                    })
                    .collect::<wasmtime::Result<Vec<_>>>(),
                Some(other) => Err(wasmtime::Error::msg(format!(
                    "async map parameter was not a map: {other:?}"
                ))),
                None => Err(wasmtime::Error::msg("async map parameter was missing")),
            };
            let entries = match entries {
                Ok(entries) => entries,
                Err(error) => return Box::pin(async move { Err(error) }),
            };
            if results.len() != 1 {
                return Box::pin(async move {
                    Err(wasmtime::Error::msg(format!(
                        "async map result arity was {}, expected 1",
                        results.len()
                    )))
                });
            }
            if entries != [(7, 70), (9, 90)] {
                host_stats.input_mismatches.fetch_add(1, Ordering::SeqCst);
            }
            host_stats.host_calls.fetch_add(1, Ordering::SeqCst);
            let completion = MapCompletion {
                stats: Arc::clone(&host_stats),
                plan: plan_for(mode),
                polled: false,
                completed: false,
            };
            Box::pin(async move {
                completion.await?;
                results[0] = Val::U32(42);
                Ok(())
            })
        }),
    )?;

    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let mut returned_result = 0;
    let call = store.run_concurrent(async |accessor| run.call_concurrent(accessor, ()).await);
    if mode.is_cancelled() {
        match select(
            Box::pin(call),
            Box::pin(CancelAfterHostCall {
                stats: Arc::clone(&stats),
            }),
        )
        .await
        {
            Either::Left((result, _cancel)) => {
                let result = map_wasmtime(result)?;
                let _ = map_wasmtime(result)?;
                bail!("{mode:?} mode completed the root task before drop");
            }
            Either::Right((_cancel, pending_call)) => {
                stats.guest_cancelled.store(true, Ordering::SeqCst);
                drop(pending_call);
            }
        }
    } else {
        let result = map_wasmtime(call.await)?;
        let (value,) = map_wasmtime(result)?;
        returned_result = value;
    }

    let result = if mode.is_cancelled() {
        0
    } else {
        returned_result
    };
    let table_empty = store.data().table.is_empty();
    drop(store);

    let host_calls = stats.host_calls.load(Ordering::SeqCst);
    let input_mismatches = stats.input_mismatches.load(Ordering::SeqCst);
    let polls = stats.polls.load(Ordering::SeqCst);
    let wakes = stats.wakes.load(Ordering::SeqCst);
    let completions = stats.completions.load(Ordering::SeqCst);
    let future_drops = stats.future_drops.load(Ordering::SeqCst);
    let pending_future_drops = stats.pending_future_drops.load(Ordering::SeqCst);
    if host_calls != 1 || input_mismatches != 0 || future_drops != 1 || !table_empty {
        bail!(
            "async map observations invalid: mode={mode:?} calls={host_calls} input-mismatches={input_mismatches} polls={polls} wakes={wakes} completions={completions} future-drops={future_drops} pending-future-drops={pending_future_drops} table-empty={table_empty}"
        );
    }
    if mode.is_cancelled() {
        if completions != 0 || pending_future_drops != 1 {
            bail!(
                "async map cancellation observations invalid: mode={mode:?} polls={polls} wakes={wakes} completions={completions} pending-future-drops={pending_future_drops}"
            );
        }
    } else {
        if result != 42 || completions != 1 || pending_future_drops != 0 {
            bail!(
                "async map completion observations invalid: mode={mode:?} result={result} polls={polls} wakes={wakes} completions={completions} pending-future-drops={pending_future_drops}"
            );
        }
    }

    println!(
        "mode={} entries=[7->70, 9->90] input-mismatches={} result={} polls={} wakes={} completions={} future-drops={} pending-future-drops={} frame-frees=1 table-empty={}",
        match mode {
            Mode::Ready => "ready",
            Mode::Pending => "pending",
            Mode::Cancel => "cancel",
            Mode::Drop => "drop",
        },
        input_mismatches,
        result,
        polls,
        wakes,
        completions,
        future_drops,
        pending_future_drops,
        table_empty,
    );
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: do-p3-async-map-capability-host-runner <component.wasm> <mode>")?;
    let mode = args
        .next()
        .context("usage: do-p3-async-map-capability-host-runner <component.wasm> <mode>")
        .and_then(|value| Mode::parse(&value))?;
    if args.next().is_some() {
        bail!("usage: do-p3-async-map-capability-host-runner <component.wasm> <mode>");
    }
    futures::executor::block_on(run(Path::new(&component_path), mode))
}
