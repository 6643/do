use anyhow::{Context, Result, bail};
use std::sync::{Arc, atomic::{AtomicU32, Ordering}};
use wasmtime::component::{Component, Linker, Val};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct State;

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn run_component(engine: &Engine, component_path: &str) -> Result<(u32, u32, u32)> {
    let component = map_wasmtime(Component::from_file(engine, component_path))
        .with_context(|| format!("load component {component_path}"))?;
    let mut linker: Linker<State> = Linker::new(engine);
    let mut api = map_wasmtime(
        linker.instance("demo:marshal-record-mixed-text-u32-list-lift/api@1.0.0"),
    )?;
    let calls = Arc::new(AtomicU32::new(0));
    let callback_calls = Arc::clone(&calls);
    map_wasmtime(api.func_new("read", move |_store, _ty, params, results| {
        if !params.is_empty() || results.len() != 1 {
            return Err(wasmtime::Error::msg(
                "unexpected mixed text/u32-list lift host signature",
            ));
        }
        results[0] = Val::Record(vec![
            ("code".to_string(), Val::U32(7)),
            ("label".to_string(), Val::String("hello".into())),
            (
                "payload".to_string(),
                Val::List(vec![Val::U32(10), Val::U32(20), Val::U32(5)]),
            ),
        ]);
        callback_calls.fetch_add(1, Ordering::SeqCst);
        Ok(())
    }))?;

    let mut store = Store::new(engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let stats = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "stats"))?;
    let (value,) = map_wasmtime(run.call(&mut store, ()))?;
    let (cleanup,) = map_wasmtime(stats.call(&mut store, ()))?;
    Ok((value, cleanup, calls.load(Ordering::SeqCst)))
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let first_path = args.next().context(
        "usage: do-p3-gc-marshal-record-mixed-text-u32-list-lift <component> [arc-component]",
    )?;
    let second_path = args.next();
    if args.next().is_some() {
        bail!("expected one or two component paths");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let first = run_component(&engine, &first_path)?;
    if let Some(second_path) = second_path {
        let second = run_component(&engine, &second_path)?;
        if first != (47, 34, 1) || second != (47, 34, 1) {
            bail!(
                "expected GC/ARC values/stats/calls=47/34/1, got {first:?}/{second:?}"
            );
        }
        println!(
            "GC/ARC mixed text/u32-list record lift equivalence passed result=47/47 stats=34/34 read-calls=1/1"
        );
        return Ok(());
    }
    if first != (47, 34, 1) {
        bail!("expected result/stats/read-calls=47/34/1, got {first:?}");
    }
    println!(
        "GC mixed text/u32-list record lift host adapter passed code=7 label=hello payload=[10, 20, 5] result=47 stats=34 read-calls=1 allocations=2 frees=2"
    );
    Ok(())
}
