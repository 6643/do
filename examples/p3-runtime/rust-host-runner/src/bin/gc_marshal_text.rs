use anyhow::{Context, Result, bail};
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct State {
    values: Vec<String>,
}

struct Outcome {
    values: Vec<String>,
    cleanup: Option<(u32, u32)>,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn run_component(
    engine: &Engine,
    component_path: &str,
    api_instance: &str,
    returns_cleanup: bool,
) -> Result<Outcome> {
    let component = map_wasmtime(Component::from_file(engine, component_path))
        .with_context(|| format!("load component {component_path}"))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut api = map_wasmtime(linker.instance(api_instance))?;
    map_wasmtime(api.func_wrap("send", |mut store, (value,): (String,)| {
        store.data_mut().values.push(value);
        Ok(())
    }))?;

    let mut store = Store::new(engine, State::default());
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let cleanup = if returns_cleanup {
        let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
        let (packed,) = map_wasmtime(run.call(&mut store, ()))?;
        Some((packed / 16, packed % 16))
    } else {
        let run = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, "run"))?;
        map_wasmtime(run.call(&mut store, ()))?;
        None
    };

    Ok(Outcome {
        values: store.data().values.clone(),
        cleanup,
    })
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let first_path = args.next().context(
        "usage: do-p3-gc-marshal-text-host-runner <component.wasm> [arc-component.wasm]",
    )?;
    let second_path = args.next();
    if args.next().is_some() {
        bail!("expected one or two component paths");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;

    let first = if let Some(second_path) = second_path {
        let gc = run_component(
            &engine,
            &first_path,
            "demo:marshal-equivalence/api@1.0.0",
            true,
        )?;
        let arc = run_component(
            &engine,
            &second_path,
            "demo:marshal-equivalence/api@1.0.0",
            true,
        )?;
        if gc.values != ["hello"] || arc.values != ["hello"] {
            bail!(
                "expected both host values hello, got {:?} and {:?}",
                gc.values,
                arc.values
            );
        }
        if gc.cleanup != Some((1, 1)) || arc.cleanup != Some((1, 1)) {
            bail!(
                "expected one allocation and free in both paths, got {:?} and {:?}",
                gc.cleanup,
                arc.cleanup
            );
        }
        println!("GC/ARC text marshal equivalence passed values=hello allocations=1/1 frees=1/1");
        return Ok(());
    } else {
        run_component(&engine, &first_path, "demo:marshal-host/api@1.0.0", false)?
    };

    if first.values.as_slice() != ["hello"] {
        bail!("expected one host value hello, got {:?}", first.values);
    }
    println!("GC text marshal host adapter passed value=hello");
    Ok(())
}
