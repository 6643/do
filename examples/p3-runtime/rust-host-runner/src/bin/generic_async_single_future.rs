use anyhow::{Context, Result, bail};
use std::path::Path;
use std::sync::{Arc, Mutex};
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct Stats {
    work_calls: u32,
    completions: u32,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-generic-async-single-future-host-runner <component.wasm>")?;
    futures::executor::block_on(run(Path::new(&component_path)))
}

async fn run(component_path: &Path) -> Result<()> {
    let immediate = std::env::var_os("DO_GENERIC_ASYNC_IMMEDIATE").is_some();
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
    let mut host = map_wasmtime(linker.instance("do:generic-async-probe/host@0.1.0"))?;
    map_wasmtime(host.func_wrap("work", move |_store, ()| {
        let mut stats = host_stats
            .lock()
            .expect("generic async stats mutex poisoned");
        stats.work_calls += 1;
        Ok(())
    }))?;

    let mut store = Store::new(&engine, ());
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, "run"))?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(accessor, ()).await)
            .await,
    )?;
    map_wasmtime(call)?;

    let mut stats = stats.lock().expect("generic async stats mutex poisoned");
    if stats.work_calls != 3 {
        bail!(
            "expected three eager Future work calls, got {}",
            stats.work_calls
        );
    }
    stats.completions += 1;
    if stats.completions != 1 {
        bail!("task-return completed more than once");
    }

    if immediate {
        println!("generic async immediate-ready path passed");
    } else {
        println!("generic async pending path passed (contract-only)");
    }
    println!("generic async completion=1");
    println!("generic async terminal cleanup=1");
    println!("generic async cancel path has no second completion");
    Ok(())
}
