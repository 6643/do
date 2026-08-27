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
    cleanup: u32,
    calls: u32,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn payload_values(fields: &[(String, Val)]) -> Result<Vec<u32>> {
    let payload = fields
        .iter()
        .find(|(name, _)| name == "payload")
        .context("mixed text/u32-list lower payload field is missing")?;
    let values = match &payload.1 {
        Val::List(values) => values,
        other => bail!("mixed text/u32-list lower payload was not a list: {other:?}"),
    };
    values
        .iter()
        .map(|value| match value {
            Val::U32(value) => Ok(*value),
            other => bail!("mixed text/u32-list lower payload element was not u32: {other:?}"),
        })
        .collect()
}

fn run_component(engine: &Engine, path: &str) -> Result<Outcome> {
    let component = map_wasmtime(Component::from_file(engine, path))
        .with_context(|| format!("load component {path}"))?;
    let mut linker: Linker<State> = Linker::new(engine);
    let mut api = map_wasmtime(
        linker.instance("demo:marshal-record-mixed-text-u32-list-lower/api@1.0.0"),
    )?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("write", move |_store, _ty, params, results| {
        if params.len() != 1 || !results.is_empty() {
            return Err(wasmtime::Error::msg(
                "unexpected mixed text/u32-list lower signature",
            ));
        }
        let fields = match &params[0] {
            Val::Record(fields) => fields,
            _ => return Err(wasmtime::Error::msg("lower parameter was not a record")),
        };
        if fields.len() != 3 {
            return Err(wasmtime::Error::msg(
                "expected three mixed text/u32-list lower fields",
            ));
        }
        let code = match fields.iter().find(|(name, _)| name == "code") {
            Some((_, Val::U32(value))) => *value,
            _ => return Err(wasmtime::Error::msg("code was not u32")),
        };
        let label = match fields.iter().find(|(name, _)| name == "label") {
            Some((_, Val::String(value))) => value,
            _ => return Err(wasmtime::Error::msg("label was not string")),
        };
        let payload =
            payload_values(fields).map_err(|error| wasmtime::Error::msg(error.to_string()))?;
        if code != 7 || label != "hello" || payload != [10, 20, 5] {
            return Err(wasmtime::Error::msg(format!(
                "unexpected mixed text/u32-list lower values code={code} label={label:?} payload={payload:?}"
            )));
        }
        callback_calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }))?;

    let mut store = Store::new(engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (cleanup,) = map_wasmtime(run.call(&mut store, ()))?;
    Ok(Outcome {
        cleanup,
        calls: calls.load(Ordering::SeqCst),
    })
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let gc_path = args.next().context(
        "usage: do-p3-gc-marshal-record-mixed-text-u32-list-lower-equivalence-runner <gc> <arc>",
    )?;
    let arc_path = args.next().context(
        "usage: do-p3-gc-marshal-record-mixed-text-u32-list-lower-equivalence-runner <gc> <arc>",
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
    if gc.cleanup != 34 || arc.cleanup != 34 || gc.calls != 1 || arc.calls != 1 {
        bail!(
            "expected cleanup=34/34 and write-calls=1/1, got cleanup={}/{} write-calls={}/{}",
            gc.cleanup,
            arc.cleanup,
            gc.calls,
            arc.calls
        );
    }
    println!(
        "GC/ARC mixed text/u32-list record lower equivalence passed code=7 label=hello payload=[10, 20, 5] allocations=2/2 frees=2/2 write-calls=1/1"
    );
    Ok(())
}
