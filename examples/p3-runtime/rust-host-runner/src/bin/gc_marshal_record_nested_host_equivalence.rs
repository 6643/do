use anyhow::{Context, Result, bail};
use wasmtime::component::{Component, Linker, Val};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct State;

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn run_component(engine: &Engine, component_path: &str) -> Result<u32> {
    let component = map_wasmtime(Component::from_file(engine, component_path))
        .with_context(|| format!("load component {component_path}"))?;
    let mut linker: Linker<State> = Linker::new(engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-record-nested-host/api@1.0.0"))?;
    map_wasmtime(api.func_new("read", |_store, _ty, params, results| {
        if !params.is_empty() || results.len() != 1 {
            return Err(wasmtime::Error::msg(
                "unexpected nested record host signature",
            ));
        }
        results[0] = Val::Record(vec![
            (
                "header".to_string(),
                Val::Record(vec![
                    ("code".to_string(), Val::U32(7)),
                    ("count".to_string(), Val::U64(35)),
                ]),
            ),
            ("status".to_string(), Val::S64(-5)),
        ]);
        Ok(())
    }))?;

    let mut store = Store::new(engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (sum,) = map_wasmtime(run.call(&mut store, ()))?;
    Ok(sum)
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let gc_path = args
        .next()
        .context("usage: do-p3-gc-marshal-record-nested-host-equivalence-runner <gc> <arc>")?;
    let arc_path = args
        .next()
        .context("usage: do-p3-gc-marshal-record-nested-host-equivalence-runner <gc> <arc>")?;
    if args.next().is_some() {
        bail!("expected two component paths");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let gc_sum = run_component(&engine, &gc_path)?;
    let arc_sum = run_component(&engine, &arc_path)?;
    if gc_sum != 37 || arc_sum != 37 {
        bail!("expected GC/ARC sums 37/37, got {gc_sum}/{arc_sum}");
    }
    println!(
        "GC/ARC manifest nested scalar record lift equivalence passed sums={gc_sum}/{arc_sum}"
    );
    Ok(())
}
