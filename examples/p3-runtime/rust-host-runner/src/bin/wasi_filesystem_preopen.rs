use anyhow::{Context, Result, bail};
use std::path::Path;
use wasmtime::component::{Component, HasSelf, Linker, Resource, ResourceTable};
use wasmtime::{Config, Engine, Store};

pub enum Descriptor {
    Dir,
    File,
}

wasmtime::component::bindgen!({
    path: "../wit/wasi-filesystem-preopen.wit",
    world: "preopen-probe",
    with: {
        "wasi:filesystem/types.descriptor": Descriptor,
    },
});

#[derive(Default)]
struct Stats {
    create: u32,
    open: u32,
    sync: u32,
    drop: u32,
}
struct State {
    table: ResourceTable,
    stats: Stats,
}

impl wasi::filesystem::types::Host for State {}
impl wasi::filesystem::types::HostDescriptor for State {
    fn open_at(
        &mut self,
        descriptor: Resource<Descriptor>,
        _path_flags: u32,
        _path: String,
        _open_flags: u32,
        _descriptor_flags: u32,
    ) -> Result<Resource<Descriptor>, wasi::filesystem::types::ErrorCode> {
        if !matches!(self.table.get(&descriptor), Ok(Descriptor::Dir)) {
            return Err(wasi::filesystem::types::ErrorCode::Unknown);
        }
        let file = self
            .table
            .push(Descriptor::File)
            .map_err(|_| wasi::filesystem::types::ErrorCode::Unknown)?;
        self.stats.open += 1;
        Ok(file)
    }

    fn sync(
        &mut self,
        descriptor: Resource<Descriptor>,
    ) -> Result<(), wasi::filesystem::types::ErrorCode> {
        if !matches!(self.table.get(&descriptor), Ok(Descriptor::File)) {
            return Err(wasi::filesystem::types::ErrorCode::Unknown);
        }
        self.stats.sync += 1;
        Ok(())
    }

    fn drop(&mut self, descriptor: Resource<Descriptor>) -> wasmtime::Result<()> {
        self.table.delete(descriptor)?;
        self.stats.drop += 1;
        Ok(())
    }
}

impl wasi::filesystem::preopens::Host for State {
    fn get_directories(&mut self) -> Vec<(Resource<Descriptor>, String)> {
        self.stats.create += 1;
        let descriptor = self
            .table
            .push(Descriptor::Dir)
            .expect("ResourceTable accepts one preopen descriptor");
        vec![(descriptor, "/".to_owned())]
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error}"))
}

fn main() -> Result<()> {
    let path = std::env::args()
        .nth(1)
        .context("usage: do-p3-wasi-filesystem-preopen-host-runner <component.wasm>")?;
    run(Path::new(&path))
}

fn run(path: &Path) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, path))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    map_wasmtime(wasi::filesystem::types::add_to_linker::<
        State,
        HasSelf<State>,
    >(&mut linker, |state| state))?;
    map_wasmtime(wasi::filesystem::preopens::add_to_linker::<
        State,
        HasSelf<State>,
    >(&mut linker, |state| state))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Stats::default(),
        },
    );
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (result,) = map_wasmtime(run.call(&mut store, ()))?;
    if result != 1
        || store.data().stats.create != 1
        || store.data().stats.open != 1
        || store.data().stats.sync != 1
        || store.data().stats.drop != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected preopen stats: result={result} create={} open={} sync={} drop={}",
            store.data().stats.create,
            store.data().stats.open,
            store.data().stats.sync,
            store.data().stats.drop
        );
    }
    println!("Rust WASI filesystem preopen adapter passed");
    println!("preopen create=1");
    println!("preopen open=1");
    println!("preopen sync=1");
    println!("preopen drop=2");
    Ok(())
}
