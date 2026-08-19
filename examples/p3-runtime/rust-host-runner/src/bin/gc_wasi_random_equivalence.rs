use anyhow::{bail, Context, Result};
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};

#[derive(Clone, Default)]
struct State {
    calls: u32,
    lengths: Vec<u64>,
    values: Vec<Vec<u8>>,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn run_component(engine: &Engine, component_path: &str) -> Result<(u32, State)> {
    let component = map_wasmtime(Component::from_file(engine, component_path))?;
    let mut linker: Linker<State> = Linker::new(engine);
    let mut random = map_wasmtime(linker.instance("wasi:random/random@0.3.0-rc-2025-09-16"))?;
    map_wasmtime(
        random.func_wrap("get-random-bytes", |mut store, (len,): (u64,)| {
            if len != 16 {
                return Err(wasmtime::Error::msg(format!(
                    "expected bounded probe length 16, got {len}"
                )));
            }
            let value = vec![0xa5; len as usize];
            let state = store.data_mut();
            state.calls += 1;
            state.lengths.push(len);
            state.values.push(value.clone());
            Ok((value,))
        }),
    )?;

    let mut store = Store::new(engine, State::default());
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (length,) = map_wasmtime(run.call(&mut store, ()))?;
    Ok((length, store.data().clone()))
}

fn main() -> Result<()> {
    let gc_component_path = std::env::args().nth(1).context(
        "usage: do-p3-gc-wasi-random-equivalence-runner <gc.component.wasm> <arc.component.wasm>",
    )?;
    let arc_component_path = std::env::args().nth(2).context(
        "usage: do-p3-gc-wasi-random-equivalence-runner <gc.component.wasm> <arc.component.wasm>",
    )?;
    if std::env::args().nth(3).is_some() {
        bail!("expected two component paths");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;

    let (gc_length, gc_state) = run_component(&engine, &gc_component_path)?;
    let (arc_length, arc_state) = run_component(&engine, &arc_component_path)?;
    let expected_values = vec![vec![0xa5; 16]];
    if gc_length != 16
        || arc_length != 16
        || gc_state.calls != 1
        || arc_state.calls != 1
        || gc_state.lengths.as_slice() != [16]
        || arc_state.lengths.as_slice() != [16]
        || gc_state.values != expected_values
        || arc_state.values != expected_values
    {
        bail!(
            "expected equivalent 16-byte random values, got gc=({gc_length}, {:?}, {:?}, {:?}) arc=({arc_length}, {:?}, {:?}, {:?})",
            gc_state.calls,
            gc_state.lengths,
            gc_state.values,
            arc_state.calls,
            arc_state.lengths,
            arc_state.values
        );
    }
    println!(
        "GC/ARC WASI random list<u8> equivalence passed lengths={gc_length}/{arc_length} bytes=16/16 calls=1/1"
    );
    Ok(())
}
