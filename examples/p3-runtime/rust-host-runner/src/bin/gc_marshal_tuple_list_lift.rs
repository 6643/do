use anyhow::{Context, Result, bail};
use std::sync::{
    Arc,
    atomic::{AtomicU32, Ordering},
};
use wasmtime::component::{Component, Linker, Val};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct State;

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn run_component(engine: &Engine, component_path: &str) -> Result<(u32, u32)> {
    let component = map_wasmtime(Component::from_file(engine, component_path))
        .with_context(|| format!("load component {component_path}"))?;
    let mut linker: Linker<State> = Linker::new(engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-tuple-list-lift/api@1.0.0"))?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(
        api.func_new("receive", move |_store, _ty, params, results| {
            if !params.is_empty() || results.len() != 1 {
                return Err(wasmtime::Error::msg(
                    "unexpected Tuple list lift host signature",
                ));
            }
            results[0] = Val::Tuple(vec![
                Val::U32(7),
                Val::List(vec![Val::U8(10), Val::U8(20), Val::U8(30)]),
            ]);
            callback_calls.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }),
    )?;

    let mut store = Store::new(engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (value,) = map_wasmtime(run.call(&mut store, ()))?;
    Ok((value, calls.load(Ordering::SeqCst)))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-gc-marshal-tuple-list-lift-host-runner <component>")?;
    if std::env::args().nth(2).is_some() {
        bail!("expected exactly one component path");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let (value, calls) = run_component(&engine, &component_path)?;
    if (value, calls) != (770, 1) {
        bail!("expected result/receive-calls=770/1, got {value}/{calls}");
    }
    println!("GC Tuple byte-list lift host execution passed result=770 receive-calls=1");
    Ok(())
}
