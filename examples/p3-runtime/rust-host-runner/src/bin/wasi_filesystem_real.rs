use anyhow::{Context, Result, bail};
use std::fs::{File, OpenOptions};
use std::path::{Path, PathBuf};
use wasmtime::component::{Component, HasSelf, Linker, Resource, ResourceTable};
use wasmtime::{Config, Engine, Store};

pub enum Descriptor {
    Dir(PathBuf),
    File(File),
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
    bytes: u64,
}

struct State {
    table: ResourceTable,
    stats: Stats,
    root: PathBuf,
    missing: bool,
}

impl wasi::filesystem::types::Host for State {}
impl wasi::filesystem::types::HostDescriptor for State {
    fn open_at(
        &mut self,
        descriptor: Resource<Descriptor>,
        _path_flags: u32,
        path: String,
        _open_flags: u32,
        _descriptor_flags: u32,
    ) -> Result<Resource<Descriptor>, wasi::filesystem::types::ErrorCode> {
        let base = match self.table.get(&descriptor) {
            Ok(Descriptor::Dir(path)) => path.clone(),
            _ => return Err(wasi::filesystem::types::ErrorCode::Unknown),
        };
        let relative = if self.missing {
            "missing"
        } else {
            path.as_str()
        };
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(base.join(relative))
            .map_err(|_| wasi::filesystem::types::ErrorCode::Unknown)?;
        self.stats.open += 1;
        self.stats.bytes += file.metadata().map(|metadata| metadata.len()).unwrap_or(0);
        self.table
            .push(Descriptor::File(file))
            .map_err(|_| wasi::filesystem::types::ErrorCode::Unknown)
    }

    fn sync(
        &mut self,
        descriptor: Resource<Descriptor>,
    ) -> Result<(), wasi::filesystem::types::ErrorCode> {
        match self.table.get(&descriptor) {
            Ok(Descriptor::File(file)) => file
                .sync_all()
                .map_err(|_| wasi::filesystem::types::ErrorCode::Unknown),
            _ => Err(wasi::filesystem::types::ErrorCode::Unknown),
        }?;
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
            .push(Descriptor::Dir(self.root.clone()))
            .expect("ResourceTable accepts one preopen descriptor");
        vec![(descriptor, self.root.display().to_string())]
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error}"))
}

fn run(component_path: &Path, root: PathBuf, missing: bool) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))?;
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
            root,
            missing,
        },
    );
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (result,) = map_wasmtime(run.call(&mut store, ()))?;
    let stats = &store.data().stats;
    let expected_open = if missing { 0 } else { 1 };
    let expected_sync = if missing { 0 } else { 1 };
    let expected_drop = if missing { 1 } else { 2 };
    if result != 1
        || stats.create != 1
        || stats.open != expected_open
        || stats.sync != expected_sync
        || stats.drop != expected_drop
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected real filesystem stats: result={result} create={} open={} sync={} drop={} bytes={} table-empty={}",
            stats.create,
            stats.open,
            stats.sync,
            stats.drop,
            stats.bytes,
            store.data().table.is_empty(),
        );
    }
    println!(
        "real-filesystem passed missing={} create={} open={} sync={} drop={} bytes={} table-empty=true",
        missing, stats.create, stats.open, stats.sync, stats.drop, stats.bytes
    );
    Ok(())
}

fn main() -> Result<()> {
    let component = std::env::args()
        .nth(1)
        .context("usage: do-p3-wasi-filesystem-real <component.wasm>")?;
    let root =
        std::env::var_os("DO_D2_FILESYSTEM_ROOT").context("DO_D2_FILESYSTEM_ROOT is required")?;
    let missing = std::env::var_os("DO_D2_FILESYSTEM_MISSING").is_some();
    run(Path::new(&component), PathBuf::from(root), missing)
}
