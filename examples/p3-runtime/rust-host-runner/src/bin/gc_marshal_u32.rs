use anyhow::{Context, Result, bail};
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct State {
    values: Vec<Vec<u32>>,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-gc-marshal-u32-host-runner <component.wasm>")?;
    if std::env::args().nth(2).is_some() {
        bail!("expected one component path");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, &component_path))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-u32-host/api@1.0.0"))?;
    map_wasmtime(api.func_wrap("send", |mut store, (value,): (Vec<u32>,)| {
        store.data_mut().values.push(value);
        Ok(())
    }))?;

    let mut store = Store::new(&engine, State::default());
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, "run"))?;
    map_wasmtime(run.call(&mut store, ()))?;

    if store.data().values.as_slice() != [vec![10, 20, 30]] {
        bail!(
            "expected one host value [10, 20, 30], got {:?}",
            store.data().values
        );
    }
    println!("GC list<u32> host adapter passed values=[10, 20, 30]");
    Ok(())
}
