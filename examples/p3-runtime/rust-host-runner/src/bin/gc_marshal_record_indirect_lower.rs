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

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: gc-marshal-record-indirect-lower <component.wasm>")?;
    if std::env::args().nth(2).is_some() {
        bail!("expected one component path");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, &component_path))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-record-indirect-lower/api@1.0.0"))?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("write", move |_store, _ty, params, results| {
        if params.len() != 1 || !results.is_empty() {
            return Err(wasmtime::Error::msg(format!(
                "unexpected indirect scalar record signature params={params:?} results={results:?}"
            )));
        }
        let fields = match &params[0] {
            Val::Record(fields) => fields,
            _ => return Err(wasmtime::Error::msg("record lower parameter was not a record")),
        };
        if fields.len() != 17 {
            return Err(wasmtime::Error::msg(format!(
                "unexpected indirect record field count {}",
                fields.len()
            )));
        }
        for (index, (name, value)) in fields.iter().enumerate() {
            let expected_name = format!("f{index}");
            let expected_value = (index + 1) as u64;
            if name != &expected_name || !matches!(value, Val::U64(actual) if *actual == expected_value) {
                return Err(wasmtime::Error::msg(format!(
                    "unexpected indirect record field {name}={value:?}, expected {expected_name}={expected_value}"
                )));
            }
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
        bail!(
            "expected result=42 and write-calls=1, got result={result} write-calls={callback_count}"
        );
    }
    println!(
        "GC indirect scalar record lower host adapter passed result={result} write-calls={callback_count}"
    );
    Ok(())
}
