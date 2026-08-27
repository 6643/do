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
        .context("usage: do-p3-gc-marshal-record-nested-lower-host-runner <component>")?;
    if std::env::args().nth(2).is_some() {
        bail!("expected one component path");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, &component_path))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-record-nested-lower/api@1.0.0"))?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("write", move |_store, _ty, params, results| {
        if params.len() != 1 || !results.is_empty() {
            return Err(wasmtime::Error::msg(
                "unexpected nested scalar record lower signature",
            ));
        }
        let fields = match &params[0] {
            Val::Record(fields) => fields,
            _ => {
                return Err(wasmtime::Error::msg(
                    "nested record lower parameter was not a record",
                ));
            }
        };
        if fields.len() != 2 {
            return Err(wasmtime::Error::msg(format!(
                "unexpected nested record field count {}",
                fields.len()
            )));
        }
        let header = match fields.iter().find(|(name, _)| name == "header") {
            Some((_, Val::Record(fields))) => fields,
            _ => {
                return Err(wasmtime::Error::msg(
                    "nested record header was not a record",
                ));
            }
        };
        let code = match header.iter().find(|(name, _)| name == "code") {
            Some((_, Val::U32(value))) => *value,
            _ => return Err(wasmtime::Error::msg("nested record code was not u32")),
        };
        let count = match header.iter().find(|(name, _)| name == "count") {
            Some((_, Val::U64(value))) => *value,
            _ => return Err(wasmtime::Error::msg("nested record count was not u64")),
        };
        let status = match fields.iter().find(|(name, _)| name == "status") {
            Some((_, Val::S64(value))) => *value,
            _ => return Err(wasmtime::Error::msg("nested record status was not s64")),
        };
        if code != 7 || count != 35 || status != -5 {
            return Err(wasmtime::Error::msg(format!(
                "unexpected nested record values code={code} count={count} status={status}"
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
        bail!(
            "expected result=42 and write-calls=1, got result={result} write-calls={callback_count}"
        );
    }
    println!(
        "GC nested scalar record lower host adapter passed result={result} write-calls={callback_count}"
    );
    Ok(())
}
