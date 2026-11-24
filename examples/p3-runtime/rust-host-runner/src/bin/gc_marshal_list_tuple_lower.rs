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

fn tuple_values(value: &Val) -> Result<(u32, i64)> {
    let fields = match value {
        Val::Tuple(fields) if fields.len() == 2 => fields,
        other => bail!("list Tuple element was not a two-field Tuple: {other:?}"),
    };
    let first = match &fields[0] {
        Val::U32(value) => *value,
        other => bail!("list Tuple first field was not u32: {other:?}"),
    };
    let second = match &fields[1] {
        Val::S64(value) => *value,
        other => bail!("list Tuple second field was not s64: {other:?}"),
    };
    Ok((first, second))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-gc-marshal-list-tuple-lower-host-runner <component>")?;
    if std::env::args().nth(2).is_some() {
        bail!("expected exactly one component path");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, &component_path))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-list-tuple-lower/api@1.0.0"))?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("send", move |_store, _ty, params, results| {
        if params.len() != 1 || !results.is_empty() {
            return Err(wasmtime::Error::msg("unexpected list Tuple lower signature"));
        }
        let values = match &params[0] {
            Val::List(values) => values,
            other => {
                return Err(wasmtime::Error::msg(format!(
                    "list Tuple lower parameter was not a list: {other:?}"
                )));
            }
        };
        let tuples: Result<Vec<_>> = values.iter().map(tuple_values).collect();
        let tuples = tuples.map_err(|error| wasmtime::Error::msg(error.to_string()))?;
        if tuples != [(10, 20), (30, 40)] {
            return Err(wasmtime::Error::msg(format!(
                "unexpected list Tuple lower values: {tuples:?}"
            )));
        }
        callback_calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }))?;

    let mut store = Store::new(&engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (result,) = map_wasmtime(run.call(&mut store, ()))?;
    let callback_count = calls.load(Ordering::SeqCst);
    if result != 42 || callback_count != 1 {
        bail!("expected result=42 send-calls=1, got result={result} send-calls={callback_count}");
    }
    println!("GC list Tuple lower host execution passed result=42 send-calls=1");
    Ok(())
}
