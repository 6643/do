use anyhow::{Context, Result, bail};
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct State {
    values: Vec<Vec<u32>>,
}

struct Outcome {
    values: Vec<Vec<u32>>,
    cleanup: (u32, u32),
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn run_component(engine: &Engine, component_path: &str) -> Result<Outcome> {
    let component = map_wasmtime(Component::from_file(engine, component_path))
        .with_context(|| format!("load component {component_path}"))?;
    let mut linker: Linker<State> = Linker::new(engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-u32-equivalence/api@1.0.0"))?;
    map_wasmtime(api.func_wrap("send", |mut store, (value,): (Vec<u32>,)| {
        store.data_mut().values.push(value);
        Ok(())
    }))?;

    let mut store = Store::new(engine, State::default());
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (packed,) = map_wasmtime(run.call(&mut store, ()))?;
    Ok(Outcome {
        values: store.data().values.clone(),
        cleanup: (packed / 16, packed % 16),
    })
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let gc_path = args
        .next()
        .context("usage: do-p3-gc-marshal-u32-equivalence-runner <gc> <arc>")?;
    let arc_path = args
        .next()
        .context("usage: do-p3-gc-marshal-u32-equivalence-runner <gc> <arc>")?;
    if args.next().is_some() {
        bail!("expected two component paths");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let gc = run_component(&engine, &gc_path)?;
    let arc = run_component(&engine, &arc_path)?;
    if gc.values.as_slice() != [vec![10, 20, 30]] || arc.values.as_slice() != [vec![10, 20, 30]] {
        bail!(
            "expected both host values [10, 20, 30], got {:?} and {:?}",
            gc.values,
            arc.values
        );
    }
    if gc.cleanup != (1, 1) || arc.cleanup != (1, 1) {
        bail!(
            "expected one allocation and free in both paths, got {:?} and {:?}",
            gc.cleanup,
            arc.cleanup
        );
    }
    println!(
        "GC/ARC list<u32> marshal equivalence passed values=[10, 20, 30] allocations=1/1 frees=1/1"
    );
    Ok(())
}
