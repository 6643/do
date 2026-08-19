use anyhow::{bail, Context, Result};
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct State;

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-gc-marshal-u32-lift-host-runner <component.wasm>")?;
    if std::env::args().nth(2).is_some() {
        bail!("expected one component path");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, &component_path))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-u32-lift-host/api@1.0.0"))?;
    map_wasmtime(api.func_wrap("receive", |_, (): ()| Ok((vec![10_u32, 20, 30],))))?;

    let mut store = Store::new(&engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (checksum,) = map_wasmtime(run.call(&mut store, ()))?;
    if checksum != 60 {
        bail!("expected list<u32> checksum 60, got {checksum}");
    }
    println!("GC list<u32> lift host adapter passed checksum={checksum}");
    Ok(())
}
