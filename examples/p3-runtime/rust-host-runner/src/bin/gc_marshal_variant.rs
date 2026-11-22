use anyhow::{Context, Result, bail};
use wasmtime::component::{Component, Linker, Val};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct State {
    received: Vec<Val>,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn run_component(engine: &Engine, component_path: &str, mode: &str) -> Result<()> {
    let component = map_wasmtime(Component::from_file(engine, component_path))
        .with_context(|| format!("load component {component_path}"))?;
    let mut linker: Linker<State> = Linker::new(engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-variant-gate/api@1.0.0"))?;

    if mode == "option" {
        map_wasmtime(api.func_new("send", |mut store, _ty, params, results| {
            if params != [Val::Option(Some(Box::new(Val::U32(7))))] || !results.is_empty() {
                return Err(wasmtime::Error::msg(format!("unexpected option call: {params:?}")));
            }
            store.data_mut().received.push(params[0].clone());
            Ok(())
        }))?;
    } else if mode == "variant-none" {
        map_wasmtime(api.func_new("send", |mut store, _ty, params, results| {
            if params != [Val::Variant("none".to_string(), None)] || !results.is_empty() {
                return Err(wasmtime::Error::msg(format!("unexpected unit variant call: {params:?}")));
            }
            store.data_mut().received.push(params[0].clone());
            Ok(())
        }))?;
    } else if mode == "result-text-lower" || mode == "result-scalar-lower" {
        let expected = if mode == "result-text-lower" {
            Val::Result(Ok(Some(Box::new(Val::String("hello".to_string())))))
        } else {
            Val::Result(Err(Some(Box::new(Val::U32(7)))))
        };
        map_wasmtime(api.func_new("send", move |mut store, _ty, params, results| {
            if params.len() != 1 || params[0] != expected || !results.is_empty() {
                return Err(wasmtime::Error::msg(format!("unexpected result call: {params:?}")));
            }
            store.data_mut().received.push(params[0].clone());
            Ok(())
        }))?;
    } else if mode == "result-text-lift" || mode == "result-scalar-lift" {
        let value = if mode == "result-text-lift" {
            Val::Result(Ok(Some(Box::new(Val::String("hello".to_string())))))
        } else {
            Val::Result(Err(Some(Box::new(Val::U32(7)))))
        };
        map_wasmtime(api.func_new("read", move |_store, _ty, params, results| {
            if !params.is_empty() || results.len() != 1 {
                return Err(wasmtime::Error::msg("unexpected result read signature"));
            }
            results[0] = value.clone();
            Ok(())
        }))?;
    } else {
        bail!("unknown variant marshal mode {mode}");
    }

    let mut store = Store::new(engine, State::default());
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (run_value,) = map_wasmtime(run.call(&mut store, ()))?;

    let expected_run = match mode {
        "option" | "variant-none" | "result-text-lower" => 1,
        "result-scalar-lower" => 2,
        "result-text-lift" => 0,
        "result-scalar-lift" => 1,
        _ => unreachable!(),
    };
    if run_value != expected_run {
        bail!("{mode}: expected run={expected_run}, got {run_value}");
    }

    if mode.ends_with("lower") || mode == "option" || mode == "variant-none" {
        let expected = match mode {
            "option" => Val::Option(Some(Box::new(Val::U32(7)))),
            "variant-none" => Val::Variant("none".to_string(), None),
            "result-text-lower" => Val::Result(Ok(Some(Box::new(Val::String("hello".to_string()))))),
            "result-scalar-lower" => Val::Result(Err(Some(Box::new(Val::U32(7))))),
            _ => unreachable!(),
        };
        if store.data().received.as_slice() != [expected] {
            bail!("{mode}: unexpected host value {:?}", store.data().received);
        }
    }

    if mode.starts_with("result-") {
        let allocs = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "allocs"))?;
        let frees = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "frees"))?;
        let (allocs,) = map_wasmtime(allocs.call(&mut store, ()))?;
        let (frees,) = map_wasmtime(frees.call(&mut store, ()))?;
        let expected = if mode == "result-text-lower" || mode == "result-text-lift" {
            (1, 1)
        } else {
            (0, 0)
        };
        if (allocs, frees) != expected {
            let actual = (allocs, frees);
            bail!("{mode}: expected cleanup={expected:?}, got {actual:?}");
        }
        println!("{mode}: run={run_value} cleanup={allocs}/{frees}");
    } else {
        println!("{mode}: run={run_value}");
    }
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args.next().context(
        "usage: do-p3-gc-marshal-variant <component.wasm> <mode>",
    )?;
    let mode = args.next().context("missing variant marshal mode")?;
    if args.next().is_some() {
        bail!("expected one component path and one mode");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    run_component(&engine, &component_path, &mode)
}
