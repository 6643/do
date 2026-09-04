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

fn parse_mode(value: &str) -> Result<Mode> {
    match value {
        "lower" => Ok(Mode::Lower),
        "lift" => Ok(Mode::Lift),
        other => bail!("mode must be lower or lift (got {other})"),
    }
}

#[derive(Clone, Copy)]
enum Mode {
    Lower,
    Lift,
}

fn run_lower(engine: &Engine, component_path: &str) -> Result<(u32, u32, u32)> {
    let component = map_wasmtime(Component::from_file(engine, component_path))
        .with_context(|| format!("load component {component_path}"))?;
    let mut linker: Linker<State> = Linker::new(engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-map-u32-u32/api@1.0.0"))?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("write", move |_store, _ty, params, results| {
        if params.len() != 1 || !results.is_empty() {
            return Err(wasmtime::Error::msg(format!(
                "unexpected map lower signature params={params:?} results={results:?}"
            )));
        }
        let pairs = match &params[0] {
            Val::Map(pairs) => pairs,
            other => {
                return Err(wasmtime::Error::msg(format!(
                    "map lower parameter was not a map: {other:?}"
                )));
            }
        };
        if pairs.len() != 2 {
            return Err(wasmtime::Error::msg(format!(
                "expected two map lower entries, got {pairs:?}"
            )));
        }
        let entries = pairs
            .iter()
            .map(|(key, value)| match (key, value) {
                (Val::U32(key), Val::U32(value)) => Ok((*key, *value)),
                other => Err(wasmtime::Error::msg(format!(
                    "map lower entry was not u32/u32: {other:?}"
                ))),
            })
            .collect::<std::result::Result<Vec<_>, _>>()?;
        if entries != [(7, 70), (9, 90)] {
            return Err(wasmtime::Error::msg(format!(
                "unexpected map lower entries: {entries:?}"
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
    let (cleanup,) = map_wasmtime(stats.call(&mut store, ()))?;
    Ok((result, cleanup, calls.load(Ordering::SeqCst)))
}

fn run_lift(engine: &Engine, component_path: &str) -> Result<(u32, u32, u32)> {
    let component = map_wasmtime(Component::from_file(engine, component_path))
        .with_context(|| format!("load component {component_path}"))?;
    let mut linker: Linker<State> = Linker::new(engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-map-u32-u32/api@1.0.0"))?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("read", move |_store, _ty, params, results| {
        if !params.is_empty() || results.len() != 1 {
            return Err(wasmtime::Error::msg(format!(
                "unexpected map lift signature params={params:?} results={results:?}"
            )));
        }
        results[0] = Val::Map(vec![
            (Val::U32(7), Val::U32(70)),
            (Val::U32(9), Val::U32(90)),
        ]);
        callback_calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }))?;

    let mut store = Store::new(engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let stats = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "stats"))?;
    let (result,) = map_wasmtime(run.call(&mut store, ()))?;
    let (cleanup,) = map_wasmtime(stats.call(&mut store, ()))?;
    Ok((result, cleanup, calls.load(Ordering::SeqCst)))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-gc-marshal-map-u32-u32 <component.wasm> <lower|lift>")?;
    let mode = std::env::args()
        .nth(2)
        .context("usage: do-p3-gc-marshal-map-u32-u32 <component.wasm> <lower|lift>")
        .and_then(|value| parse_mode(&value))?;
    if std::env::args().nth(3).is_some() {
        bail!("expected one component path and one mode");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_map(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let (result, stats, calls) = match mode {
        Mode::Lower => run_lower(&engine, &component_path)?,
        Mode::Lift => run_lift(&engine, &component_path)?,
    };

    let expected_result = match mode {
        Mode::Lower => 42,
        Mode::Lift => 176,
    };
    if result != expected_result || stats != 17 || calls != 1 {
        bail!(
            "expected result={expected_result} stats=17 calls=1, got result={result} stats={stats} calls={calls}"
        );
    }
    match mode {
        Mode::Lower => println!(
            "GC map<u32,u32> lower host adapter passed entries=[7->70, 9->90] result={result} stats={stats} write-calls={calls} allocations=1 frees=1"
        ),
        Mode::Lift => println!(
            "GC map<u32,u32> lift host adapter passed entries=[7->70, 9->90] result={result} stats={stats} read-calls={calls} allocations=1 frees=1"
        ),
    }
    Ok(())
}
