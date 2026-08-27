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
        .context("mixed scalar-list lower payload field is missing")?;
    let values = match &payload.1 {
        Val::List(values) => values,
        other => bail!("mixed scalar-list lower payload was not a list: {other:?}"),
    };
    values
        .iter()
        .map(|value| match value {
            Val::U8(value) => Ok(*value),
            other => bail!("mixed scalar-list lower payload element was not u8: {other:?}"),
        })
        .collect()
}

fn main() -> Result<()> {
    let component_path = std::env::args().nth(1).context(
        "usage: do-p3-gc-marshal-record-mixed-scalar-list-lower-host-runner <component>",
    )?;
    if std::env::args().nth(2).is_some() {
        bail!("expected one component path");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, &component_path))
        .with_context(|| format!("load component {component_path}"))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut api =
        map_wasmtime(linker.instance("demo:marshal-record-mixed-scalar-list-lower/api@1.0.0"))?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("write", move |_store, _ty, params, results| {
        if params.len() != 1 || !results.is_empty() {
            return Err(wasmtime::Error::msg(format!(
                "unexpected mixed scalar-list lower signature params={params:?} results={results:?}"
            )));
        }
        let fields = match &params[0] {
            Val::Record(fields) => fields,
            _ => return Err(wasmtime::Error::msg("lower parameter was not a record")),
        };
        if fields.len() != 3 {
            return Err(wasmtime::Error::msg(format!(
                "expected three mixed scalar-list lower fields, got {fields:?}"
            )));
        }
        let code = match fields.iter().find(|(name, _)| name == "code") {
            Some((_, Val::U32(value))) => *value,
            _ => return Err(wasmtime::Error::msg("code was not u32")),
        };
        let label = match fields.iter().find(|(name, _)| name == "label") {
            Some((_, Val::String(value))) => value,
            _ => return Err(wasmtime::Error::msg("label was not string")),
        };
        let payload = payload_bytes(fields).map_err(|error| wasmtime::Error::msg(error.to_string()))?;
        if code != 7 || label != "hello" || payload != [10, 20, 5] {
            return Err(wasmtime::Error::msg(format!(
                "unexpected mixed scalar-list lower values code={code} label={label:?} payload={payload:?}"
            )));
        }
        callback_calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }))?;

    let mut store = Store::new(&engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (cleanup,) = map_wasmtime(run.call(&mut store, ()))?;
    let callback_count = calls.load(Ordering::SeqCst);
    if cleanup != 34 || callback_count != 1 {
        bail!(
            "expected cleanup=34 (alloc=2 free=2) and write-calls=1, got cleanup={cleanup} write-calls={callback_count}"
        );
    }
    println!(
        "GC mixed scalar-list record lower host adapter passed code=7 label=hello payload=[10, 20, 5] write-calls={callback_count} allocations=2 frees=2"
    );
    Ok(())
}
