use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{Accessor, AccessorTask, Component, Linker};
use wasmtime::{Config, Engine, Store};

#[path = "../budget_gate.rs"]
mod budget_gate;

const RESULT_INSTANCE: &str = "do:result-probe/run@0.1.0";

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error}"))
}

struct PendingWake {
    completion: oneshot::Receiver<()>,
}

struct CancellationPending {
    completion: oneshot::Receiver<()>,
    dropped: Arc<AtomicUsize>,
}

impl Future for CancellationPending {
    type Output = wasmtime::Result<()>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        match Pin::new(&mut self.completion).poll(cx) {
            Poll::Pending => Poll::Pending,
            Poll::Ready(Ok(())) => Poll::Ready(Ok(())),
            Poll::Ready(Err(_)) => Poll::Ready(Err(wasmtime::Error::msg(
                "scalar Result cancellation wake dropped",
            ))),
        }
    }
}

impl Drop for CancellationPending {
    fn drop(&mut self) {
        self.dropped.fetch_add(1, Ordering::SeqCst);
    }
}

impl Future for PendingWake {
    type Output = wasmtime::Result<()>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        match Pin::new(&mut self.completion).poll(cx) {
            Poll::Pending => Poll::Pending,
            Poll::Ready(Ok(())) => Poll::Ready(Ok(())),
            Poll::Ready(Err(_)) => {
                Poll::Ready(Err(wasmtime::Error::msg("scalar Result wake dropped")))
            }
        }
    }
}

struct Wake {
    completion: oneshot::Sender<()>,
}

impl AccessorTask<()> for Wake {
    fn run(self, _accessor: &Accessor<()>) -> impl Future<Output = wasmtime::Result<()>> + Send {
        async move {
            let _ = self.completion.send(());
            Ok(())
        }
    }
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-scalar-result-host-runner <component.wasm>")?;
    let cancellation_component_path = std::env::args().nth(2);
    futures::executor::block_on(run(
        Path::new(&component_path),
        cancellation_component_path.as_deref().map(Path::new),
    ))
}

async fn run(component_path: &Path, cancellation_component_path: Option<&Path>) -> Result<()> {
    let immediate = std::env::var_os("DO_P3_SCALAR_RESULT_IMMEDIATE").is_some();
    let budget_limit = std::env::var("DO_P3_SCALAR_RESULT_BUDGET_LIMIT")
        .ok()
        .map(|value| {
            value
                .parse::<i64>()
                .context("invalid scalar Result budget limit")
        })
        .transpose()?;
    let expect_budget_rejection =
        std::env::var_os("DO_P3_SCALAR_RESULT_BUDGET_EXPECT_REJECT").is_some();
    let scheduler_limit = std::env::var("DO_P3_SCALAR_RESULT_SCHEDULER_LIMIT")
        .ok()
        .map(|value| {
            value
                .parse::<u64>()
                .context("invalid scalar Result scheduler limit")
        })
        .transpose()?;
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);

    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))?;
    let mut linker = Linker::new(&engine);
    let mut result_instance = map_wasmtime(linker.instance(RESULT_INSTANCE))?;
    map_wasmtime(result_instance.func_wrap_concurrent(
        "run",
        move |accessor, (value,): (i32,)| {
            let result = if value >= 0 {
                Ok(value + 1)
            } else {
                Err(value - 1)
            };
            if immediate {
                return Box::pin(async move {
                    Ok::<(std::result::Result<i32, i32>,), wasmtime::Error>((result,))
                });
            }
            let (sender, receiver) = oneshot::channel();
            let wake = accessor.spawn(Wake { completion: sender });
            Box::pin(async move {
                wake?;
                PendingWake {
                    completion: receiver,
                }
                .await?;
                Ok::<(std::result::Result<i32, i32>,), wasmtime::Error>((result,))
            })
        },
    ))?;

    let mut store = Store::new(&engine, ());
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(
        instance.get_typed_func::<(i32,), (std::result::Result<i32, i32>,)>(&mut store, "run"),
    )?;

    if let Some(limit) = scheduler_limit {
        let config_limit = i64::try_from(limit).context("scheduler limit exceeds i64")?;
        let configure = map_wasmtime(
            instance.get_typed_func::<(i64,), (i32,)>(&mut store, "byte-budget-limit"),
        )?;
        let configured = map_wasmtime(configure.call_async(&mut store, (config_limit,)).await)?;
        if configured.0 != 1 {
            bail!("budget configuration rejected limit={limit}");
        }

        let gate = budget_gate::BudgetGate::new(limit);
        let first = gate
            .try_acquire(20)
            .ok_or_else(|| anyhow::anyhow!("scheduler rejected first frame limit={limit}"))?;
        if gate.try_acquire(20).is_some() {
            bail!("scheduler admitted a second frame before the first completed");
        }
        let first_result = map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |accessor| run.call_concurrent(&accessor, (42,)).await)
                .await,
        )?)?;
        if first_result.0 != Ok(43) {
            bail!("expected first scheduled Ok(43), got {:?}", first_result.0);
        }
        if gate.used() != 20 {
            bail!("scheduler permit released before first completion");
        }
        drop(first);
        if gate.used() != 0 {
            bail!("scheduler permit was not released after first completion");
        }

        let second = gate
            .try_acquire(20)
            .ok_or_else(|| anyhow::anyhow!("scheduler did not admit released frame"))?;
        let second_result = map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |accessor| run.call_concurrent(&accessor, (-9,)).await)
                .await,
        )?)?;
        if second_result.0 != Err(-10) {
            bail!(
                "expected second scheduled Err(-10), got {:?}",
                second_result.0
            );
        }
        drop(second);
        println!(
            "Rust scalar Result scheduler admission passed limit={limit} rejected=1 released=1"
        );
        return Ok(());
    }

    if let Some(limit) = budget_limit {
        let configure = map_wasmtime(
            instance.get_typed_func::<(i64,), (i32,)>(&mut store, "byte-budget-limit"),
        )?;
        let configured = map_wasmtime(configure.call_async(&mut store, (limit,)).await)?;
        if configured.0 != 1 {
            bail!("budget configuration rejected limit={limit}");
        }

        let outcome = store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, (42,)).await)
            .await;
        if expect_budget_rejection {
            match outcome {
                Ok(Ok(_)) => bail!("budget limit unexpectedly admitted frame=20 limit={limit}"),
                Ok(Err(_)) | Err(_) => {
                    println!("Rust scalar Result budget adapter rejected limit={limit} frame=20");
                    return Ok(());
                }
            }
        }

        let result = map_wasmtime(map_wasmtime(outcome)?)?;
        if result.0 != Ok(43) {
            bail!("expected budgeted Ok(43), got {:?}", result.0);
        }
        println!("Rust scalar Result budget adapter passed limit={limit} configured=1 frame=20");
        return Ok(());
    }

    let results = map_wasmtime(map_wasmtime(
        store
            .run_concurrent(async |accessor| {
                futures::try_join!(
                    run.call_concurrent(&accessor, (42,)),
                    run.call_concurrent(&accessor, (-9,)),
                )
            })
            .await,
    )?)?;

    if results.0.0 != Ok(43) {
        bail!("expected Ok(43), got {:?}", results.0.0);
    }
    if results.1.0 != Err(-10) {
        bail!("expected Err(-10), got {:?}", results.1.0);
    }
    println!(
        "Rust scalar Result {} adapter passed ok=43 err=-10",
        if immediate { "immediate" } else { "pending" }
    );
    if let Some(cancellation_component_path) = cancellation_component_path {
        run_cancellation(cancellation_component_path).await?;
    }
    Ok(())
}

async fn run_cancellation(component_path: &Path) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);

    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))?;
    let committed = Arc::new(AtomicUsize::new(0));
    let dropped = Arc::new(AtomicUsize::new(0));
    let mut linker = Linker::new(&engine);
    let mut result_instance = map_wasmtime(linker.instance(RESULT_INSTANCE))?;
    let committed_host = Arc::clone(&committed);
    let dropped_host = Arc::clone(&dropped);
    map_wasmtime(result_instance.func_wrap_concurrent(
        "run",
        move |accessor, (value,): (i32,)| {
            committed_host.fetch_add(1, Ordering::SeqCst);
            let (sender, receiver) = oneshot::channel();
            let wake = accessor.spawn(Wake { completion: sender });
            let dropped = Arc::clone(&dropped_host);
            Box::pin(async move {
                wake?;
                CancellationPending {
                    completion: receiver,
                    dropped,
                }
                .await?;
                Ok::<(std::result::Result<i32, i32>,), wasmtime::Error>((Ok(value + 1),))
            })
        },
    ))?;

    let mut store = Store::new(&engine, ());
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let cancel = map_wasmtime(instance.get_typed_func::<(i32,), ()>(&mut store, "cancel-result"))?;
    let _ = map_wasmtime(map_wasmtime(
        store
            .run_concurrent(async |accessor| cancel.call_concurrent(&accessor, (7,)).await)
            .await,
    )?)?;

    let committed = committed.load(Ordering::SeqCst);
    let dropped = dropped.load(Ordering::SeqCst);
    if committed != 1 || dropped != 1 {
        bail!(
            "expected one committed effect and one host future drop, got committed={committed} dropped={dropped}"
        );
    }
    println!(
        "Rust scalar Result cancellation adapter passed started=1 committed={committed} rollback=0 dropped={dropped}"
    );
    Ok(())
}

#[cfg(test)]
mod budget_gate_tests {
    use super::budget_gate::BudgetGate;

    #[test]
    fn gate_rejects_without_mutating_and_releases_on_drop() {
        let gate = BudgetGate::new(20);
        let first = gate.try_acquire(20).expect("first reservation");
        assert_eq!(gate.used(), 20);
        assert!(gate.try_acquire(1).is_none());
        assert_eq!(gate.used(), 20);
        drop(first);
        assert_eq!(gate.used(), 0);
        assert!(gate.try_acquire(20).is_some());
    }
}
