use anyhow::{Context, Result, bail};
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};

#[derive(Default)]
struct State {
    lengths: Vec<u64>,
    values: Vec<Vec<u8>>,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-gc-wasi-random-host-runner <component.wasm>")?;
    if std::env::args().nth(2).is_some() {
        bail!("expected one component path");
    }

    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_gc(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, &component_path))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut random = map_wasmtime(linker.instance("wasi:random/random@0.3.0-rc-2025-09-16"))?;
    map_wasmtime(
        random.func_wrap("get-random-bytes", |mut store, (len,): (u64,)| {
            if len != 16 {
                return Err(wasmtime::Error::msg(format!(
                    "expected bounded probe length 16, got {len}"
                )));
            }
            store.data_mut().lengths.push(len);
            let value = vec![0xa5; len as usize];
            store.data_mut().values.push(value.clone());
            Ok((value,))
        }),
    )?;

    let mut store = Store::new(&engine, State::default());
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (length,) = map_wasmtime(run.call(&mut store, ()))?;

    if length != 16
        || store.data().lengths.as_slice() != [16]
        || store.data().values.as_slice() != [vec![0xa5; 16]]
    {
        bail!(
            "expected one 16-byte random value, got length={length} lengths={:?} values={:?}",
            store.data().lengths,
            store.data().values
        );
    }
    println!("GC WASI random list<u8> host lift passed length=16 bytes=16");
    Ok(())
}
