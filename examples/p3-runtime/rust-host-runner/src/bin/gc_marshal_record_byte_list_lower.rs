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

fn payload_bytes(fields: &[(String, Val)]) -> Result<Vec<u8>> {
    let payload = fields
        .iter()
        .find(|(name, _)| name == "payload")
        .map(|(_, value)| value)
        .context("byte-list record payload field is missing")?;
    let values = match payload {
        Val::List(values) => values,
        _ => bail!("byte-list record payload was not a list: {payload:?}"),
    };
    values
        .iter()
        .map(|value| match value {
            Val::U8(value) => Ok(*value),
            other => bail!("byte-list payload element was not u8: {other:?}"),
        })
        .collect()
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-gc-marshal-record-byte-list-lower-host-runner <component>")?;
    if std::env::args().nth(2).is_some() {
        bail!("expected one component path");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, &component_path))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut api = map_wasmtime(
        linker.instance("demo:marshal-record-byte-list-lower/api@1.0.0"),
    )?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("write", move |_store, _ty, params, results| {
        if params.len() != 1 || !results.is_empty() {
            return Err(wasmtime::Error::msg(format!(
                "unexpected byte-list lower signature params={params:?} results={results:?}"
            )));
        }
        let fields = match &params[0] {
            Val::Record(fields) => fields,
            other => return Err(wasmtime::Error::msg(format!(
                "byte-list lower parameter was not a record: {other:?}"
            ))),
        };
        let code = match fields.iter().find(|(name, _)| name == "code") {
            Some((_, Val::U32(value))) => *value,
            _ => return Err(wasmtime::Error::msg("byte-list record code was not u32")),
        };
        let payload = payload_bytes(fields).map_err(|error| wasmtime::Error::msg(error.to_string()))?;
        if code != 7 || payload != [10, 20, 5] {
            return Err(wasmtime::Error::msg(format!(
                "unexpected byte-list record values code={code} payload={payload:?}"
            )));
        }
        callback_calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }))?;

    let mut store = Store::new(&engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let stats = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "stats"))?;
    let (result,) = map_wasmtime(run.call(&mut store, ()))?;
    let (cleanup,) = map_wasmtime(stats.call(&mut store, ()))?;
    let callback_count = calls.load(Ordering::SeqCst);
    if result != 42 || cleanup != 17 || callback_count != 1 {
        bail!(
            "expected result=42 stats=17 write-calls=1, got result={result} stats={cleanup} write-calls={callback_count}"
        );
    }
    println!(
        "GC byte-list record lower host adapter passed code=7 payload=[10, 20, 5] result={result} write-calls={callback_count} allocations=1 frees=1"
    );
    Ok(())
}
