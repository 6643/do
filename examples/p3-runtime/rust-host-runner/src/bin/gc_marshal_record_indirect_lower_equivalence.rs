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
    let mut api = map_wasmtime(linker.instance("demo:marshal-record-indirect-lower/api@1.0.0"))?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("write", move |_store, _ty, params, results| {
        if params.len() != 1 || !results.is_empty() {
            return Err(wasmtime::Error::msg(
                "unexpected indirect scalar record signature",
            ));
        }
        let fields = match &params[0] {
            Val::Record(fields) => fields,
            _ => {
                return Err(wasmtime::Error::msg(
                    "record lower parameter was not a record",
                ));
            }
        };
        if fields.len() != 17 {
            return Err(wasmtime::Error::msg(
                "unexpected indirect record field count",
            ));
        }
        for (index, (name, value)) in fields.iter().enumerate() {
            let expected_name = format!("f{index}");
            let expected_value = (index + 1) as u64;
            if name != &expected_name
                || !matches!(value, Val::U64(actual) if *actual == expected_value)
            {
                return Err(wasmtime::Error::msg(format!(
                    "unexpected indirect record field {name}={value:?}"
                )));
            }
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
        .context("usage: gc-marshal-record-indirect-lower-equivalence <gc> <flat>")?;
    let flat_path = args
        .next()
        .context("usage: gc-marshal-record-indirect-lower-equivalence <gc> <flat>")?;
    if args.next().is_some() {
        bail!("expected two component paths");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let (gc_result, gc_calls) = run_component(&engine, &gc_path)?;
    let (flat_result, flat_calls) = run_component(&engine, &flat_path)?;
    if gc_result != 42 || flat_result != 42 || gc_calls != 1 || flat_calls != 1 {
        bail!(
            "expected result=42/42 and write-calls=1/1, got result={gc_result}/{flat_result} write-calls={gc_calls}/{flat_calls}"
        );
    }
    println!(
        "GC/flat indirect scalar record lower equivalence passed results={gc_result}/{flat_result} write-calls={gc_calls}/{flat_calls}"
    );
    Ok(())
}
