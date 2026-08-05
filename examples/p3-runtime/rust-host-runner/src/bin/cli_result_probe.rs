use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{Accessor, AccessorTask, Component, Linker};
use wasmtime::{Config, Engine, Store};

const CLI_INSTANCE: &str = "wasi:cli/run@0.3.0";

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error}"))
}

#[derive(Default)]
struct Stats {
    calls: u32,
    pending_polls: u32,
    external_wakes: u32,
    completions: u32,
}

struct PendingResult {
    stats: Arc<Mutex<Stats>>,
    completion: oneshot::Receiver<()>,
    pending_recorded: bool,
}

impl Future for PendingResult {
    type Output = wasmtime::Result<()>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        match Pin::new(&mut self.completion).poll(cx) {
            Poll::Pending => {
                if self.pending_recorded {
                    return Poll::Pending;
                }
                self.pending_recorded = true;
                let mut stats = self.stats.lock().expect("cli result stats mutex poisoned");
                stats.pending_polls += 1;
                Poll::Pending
            }
            Poll::Ready(Ok(())) => {
                let mut stats = self.stats.lock().expect("cli result stats mutex poisoned");
                stats.completions += 1;
                Poll::Ready(Ok(()))
            }
            Poll::Ready(Err(_)) => {
                Poll::Ready(Err(wasmtime::Error::msg("cli run host event dropped")))
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
            let mut stats = self.stats.lock().expect("cli result stats mutex poisoned");
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
        .context("usage: cli_result_probe <component.wasm>")?;
    futures::executor::block_on(run(Path::new(&component_path)))
}

async fn run(component_path: &Path) -> Result<()> {
    let immediate = std::env::var_os("DO_P3_CLI_RESULT_IMMEDIATE").is_some();
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
    let mut cli = map_wasmtime(linker.instance(CLI_INSTANCE))?;
    map_wasmtime(cli.func_wrap_concurrent("run", move |accessor, (): ()| {
        let mut stats = host_stats.lock().expect("cli result stats mutex poisoned");
        stats.calls += 1;
        let result = Ok(());
        drop(stats);
        if immediate {
            return Box::pin(async move {
                Ok::<(std::result::Result<(), ()>,), wasmtime::Error>((result,))
            });
        }
        let (completion_sender, completion) = oneshot::channel();
        let host_event = accessor.spawn(HostWake {
            stats: Arc::clone(&host_stats),
            completion: completion_sender,
        });
        let pending = PendingResult {
            stats: Arc::clone(&host_stats),
            completion,
            pending_recorded: false,
        };
        Box::pin(async move {
            host_event?;
            pending.await?;
            Ok::<(std::result::Result<(), ()>,), wasmtime::Error>((result,))
        })
    }))?;

    let mut store = Store::new(&engine, ());
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ()>,)>(&mut store, "run"),
    )?;
    let results = map_wasmtime(map_wasmtime(
        store
            .run_concurrent(async |accessor| {
                futures::try_join!(
                    run.call_concurrent(&accessor, ()),
                    run.call_concurrent(&accessor, ()),
                )
            })
            .await,
    )?)?;
    if !results.0.0.is_err() || !results.1.0.is_err() {
        bail!("expected both guest results to invert host Ok into Err, got {results:?}");
    }

    let stats = stats.lock().expect("cli result stats mutex poisoned");
    let expected_async_stats = if immediate { (0, 0, 0) } else { (2, 2, 2) };
    if stats.calls != 2
        || (stats.pending_polls, stats.external_wakes, stats.completions) != expected_async_stats
    {
        bail!(
            "expected CLI Result stats {:?}; got calls={}, pending-polls={}, external-wakes={}, completions={}",
            expected_async_stats,
            stats.calls,
            stats.pending_polls,
            stats.external_wakes,
            stats.completions
        );
    }
    println!(
        "Rust P3 CLI Result {} adapter passed parallel-calls=2",
        if immediate { "immediate" } else { "pending" }
    );
    Ok(())
}
