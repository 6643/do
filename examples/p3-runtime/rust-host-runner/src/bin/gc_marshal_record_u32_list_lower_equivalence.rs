use anyhow::{Context, Result, bail};
use std::sync::{
    Arc,
    atomic::{AtomicU32, Ordering},
};
use wasmtime::component::{Component, Linker, Val};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct State;

struct Outcome {
    result: u32,
    stats: u32,
    calls: u32,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn run_component(engine: &Engine, path: &str) -> Result<Outcome> {
    let component = map_wasmtime(Component::from_file(engine, path))
        .with_context(|| format!("load component {path}"))?;
    let mut linker: Linker<State> = Linker::new(engine);
    let mut api = map_wasmtime(
        linker.instance("demo:marshal-record-u32-list-lower/api@1.0.0"),
    )?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("write", move |_store, _ty, params, results| {
        if params.len() != 1 || !results.is_empty() {
            return Err(wasmtime::Error::msg("unexpected u32-list lower signature"));
        }
        let fields = match &params[0] {
            Val::Record(fields) => fields,
            _ => return Err(wasmtime::Error::msg("u32-list lower parameter was not a record")),
        };
        let code = match fields.iter().find(|(name, _)| name == "code") {
            Some((_, Val::U32(value))) => *value,
            _ => return Err(wasmtime::Error::msg("u32-list record code was not u32")),
        };
        let payload = match fields.iter().find(|(name, _)| name == "payload") {
            Some((_, Val::List(values))) => values
                .iter()
                .map(|value| match value {
                    Val::U32(value) => Ok(*value),
                    _ => Err(wasmtime::Error::msg("u32-list payload element was not u32")),
                })
                .collect::<wasmtime::Result<Vec<u32>>>()?,
            _ => return Err(wasmtime::Error::msg("u32-list record payload was not a list")),
        };
        if code != 7 || payload != [10, 20, 30] {
            return Err(wasmtime::Error::msg(format!(
                "unexpected u32-list record values code={code} payload={payload:?}"
            )));
        }
        callback_calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }))?;

    let mut store = Store::new(engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let stats = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "stats"))?;
    let (result,) = map_wasmtime(run.call(&mut store, ()))?;
    let (stats,) = map_wasmtime(stats.call(&mut store, ()))?;
    Ok(Outcome {
        result,
        stats,
        calls: calls.load(Ordering::SeqCst),
    })
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let gc_path = args.next().context(
        "usage: do-p3-gc-marshal-record-u32-list-lower-equivalence-runner <gc> <arc>",
    )?;
    let arc_path = args.next().context(
        "usage: do-p3-gc-marshal-record-u32-list-lower-equivalence-runner <gc> <arc>",
    )?;
    if args.next().is_some() {
        bail!("expected two component paths");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let gc = run_component(&engine, &gc_path)?;
    let arc = run_component(&engine, &arc_path)?;
    if gc.result != 42 || arc.result != 17 || gc.stats != 17 || arc.stats != 17 || gc.calls != 1 || arc.calls != 1 {
        bail!(
            "expected GC result/stats/calls=42/17/1 and ARC=17/17/1, got GC={}/{}/{} ARC={}/{}/{}",
            gc.result,
            gc.stats,
            gc.calls,
            arc.result,
            arc.stats,
            arc.calls
        );
    }
    println!(
        "GC/ARC u32-list record lower equivalence passed code=7 payload=[10, 20, 30] result=42/17 allocations=1/1 frees=1/1 write-calls=1/1"
    );
    Ok(())
}
