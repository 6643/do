use anyhow::{bail, Context, Result};
use std::sync::{
    atomic::{AtomicU32, Ordering},
    Arc,
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
    let mut api = map_wasmtime(linker.instance("demo:marshal-record-mixed-lower/api@1.0.0"))?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("write", move |_store, _ty, params, results| {
        if params.len() != 1 || !results.is_empty() {
            return Err(wasmtime::Error::msg(
                "unexpected mixed scalar record signature",
            ));
        }
        let fields = match &params[0] {
            Val::Record(fields) => fields,
            _ => {
                return Err(wasmtime::Error::msg(
                    "record lower parameter was not a record",
                ))
            }
        };
        let code = match fields.iter().find(|(name, _)| name == "code") {
            Some((_, Val::U32(value))) => *value,
            _ => return Err(wasmtime::Error::msg("record code was not u32")),
        };
        let count = match fields.iter().find(|(name, _)| name == "count") {
            Some((_, Val::U64(value))) => *value,
            _ => return Err(wasmtime::Error::msg("record count was not u64")),
        };
        let status = match fields.iter().find(|(name, _)| name == "status") {
            Some((_, Val::S64(value))) => *value,
            _ => return Err(wasmtime::Error::msg("record status was not s64")),
        };
        if code != 7 || count != 35 || status != -5 {
            return Err(wasmtime::Error::msg(format!(
                "unexpected mixed record values {code},{count},{status}"
            )));
        }
        callback_calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }))?;

    let mut store = Store::new(engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (result,) = map_wasmtime(run.call(&mut store, ()))?;
    Ok((result, calls.load(Ordering::SeqCst)))
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let gc_path = args
        .next()
        .context("usage: do-p3-gc-marshal-record-mixed-lower-equivalence <gc> <arc>")?;
    let arc_path = args
        .next()
        .context("usage: do-p3-gc-marshal-record-mixed-lower-equivalence <gc> <arc>")?;
    if args.next().is_some() {
        bail!("expected two component paths");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let (gc_result, gc_calls) = run_component(&engine, &gc_path)?;
    let (arc_result, arc_calls) = run_component(&engine, &arc_path)?;
    if gc_result != 42 || arc_result != 42 || gc_calls != 1 || arc_calls != 1 {
        bail!(
            "expected result=42/42 and write-calls=1/1, got result={gc_result}/{arc_result} write-calls={gc_calls}/{arc_calls}"
        );
    }
    println!(
        "GC/flat mixed scalar record lower equivalence passed results={gc_result}/{arc_result} write-calls={gc_calls}/{arc_calls}"
    );
    Ok(())
}
