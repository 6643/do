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
        .context("usage: do-p3-gc-marshal-record-managed-lower-host-runner <component>")?;
    if std::env::args().nth(2).is_some() {
        bail!("expected one component path");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, &component_path))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-record-managed-lower/api@1.0.0"))?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("write", move |_store, _ty, params, results| {
        if params.len() != 1 || !results.is_empty() {
            return Err(wasmtime::Error::msg(format!(
                "unexpected managed lower signature params={params:?} results={results:?}"
            )));
        }
        let fields = match &params[0] {
            Val::Record(fields) => fields,
            _ => {
                return Err(wasmtime::Error::msg(
                    "managed lower parameter was not a record",
                ));
            }
        };
        let code = match fields.iter().find(|(name, _)| name == "code") {
            Some((_, Val::U32(value))) => *value,
            _ => return Err(wasmtime::Error::msg("managed lower code was not u32")),
        };
        let label = match fields.iter().find(|(name, _)| name == "label") {
            Some((_, Val::String(value))) => value,
            _ => return Err(wasmtime::Error::msg("managed lower label was not string")),
        };
        if code != 7 || label != "hello" {
            return Err(wasmtime::Error::msg(format!(
                "unexpected managed lower values code={code} label={label:?}"
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
    if cleanup != 17 || callback_count != 1 {
        bail!(
            "expected cleanup=17 (alloc=1 free=1) and write-calls=1, got cleanup={cleanup} write-calls={callback_count}"
        );
    }
    println!(
        "GC managed-field record lower host adapter passed code=7 label=hello write-calls={callback_count} allocations=1 frees=1"
    );
    Ok(())
}
