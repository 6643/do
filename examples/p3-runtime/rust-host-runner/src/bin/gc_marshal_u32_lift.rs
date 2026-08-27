use anyhow::{Context, Result, bail};
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct State;

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn run_component(engine: &Engine, component_path: &str) -> Result<u32> {
    let component = map_wasmtime(Component::from_file(engine, component_path))?;
    let mut linker: Linker<State> = Linker::new(engine);
    let mut api = map_wasmtime(linker.instance("demo:marshal-u32-lift-host/api@1.0.0"))?;
    map_wasmtime(api.func_wrap("receive", |_, (): ()| Ok((vec![10_u32, 20, 30],))))?;

    let mut store = Store::new(engine, State);
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (checksum,) = map_wasmtime(run.call(&mut store, ()))?;
    Ok(checksum)
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let first_path = args.next().context(
        "usage: do-p3-gc-marshal-u32-lift-host-runner <component.wasm> [arc-component.wasm]",
    )?;
    let second_path = args.next();
    if args.next().is_some() {
        bail!("expected one or two component paths");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let first_checksum = run_component(&engine, &first_path)?;
    if let Some(second_path) = second_path {
        let second_checksum = run_component(&engine, &second_path)?;
        if first_checksum != 60 || second_checksum != 60 {
            bail!(
                "expected GC/ARC list<u32> checksums 60/60, got {first_checksum}/{second_checksum}"
            );
        }
        println!(
            "GC/ARC list<u32> lift equivalence passed checksums={first_checksum}/{second_checksum}"
        );
        return Ok(());
    }
    if first_checksum != 60 {
        bail!("expected list<u32> checksum 60, got {first_checksum}");
    }
    println!("GC list<u32> lift host adapter passed checksum={first_checksum}");
    Ok(())
}
