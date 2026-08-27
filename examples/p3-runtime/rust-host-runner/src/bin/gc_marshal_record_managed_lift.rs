use anyhow::{Context, Result, bail};
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
        .context("usage: do-p3-gc-marshal-record-managed-lift-host-runner <component>")?;
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
    let mut api = map_wasmtime(linker.instance("demo:marshal-record-managed-lift/api@1.0.0"))?;
    map_wasmtime(api.func_new("read", |_store, _ty, params, results| {
        if !params.is_empty() || results.len() != 1 {
            return Err(wasmtime::Error::msg(
                "unexpected managed record host signature",
            ));
        }
        results[0] = Val::Record(vec![
            ("code".to_string(), Val::U32(7)),
            ("label".to_string(), Val::String("hello".into())),
        ]);
        Ok(())
    }))?;

    let mut store = Store::new(&engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (value,) = map_wasmtime(run.call(&mut store, ()))?;
    if value != 12 {
        bail!("expected managed record code plus label length 12, got {value}");
    }
    println!("GC managed-field record lift host adapter passed value={value}");
    Ok(())
}
