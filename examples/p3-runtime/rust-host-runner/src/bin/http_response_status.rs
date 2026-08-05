use anyhow::{Context, Result, bail};
use std::path::Path;
use wasmtime::component::{Component, HasSelf, Linker, Resource, ResourceTable};
use wasmtime::{Config, Engine, Store};

const HTTP_PROBE_INSTANCE: &str = "wasi:http/probe@0.3.0-rc-2025-09-16";

pub struct Response;

wasmtime::component::bindgen!({
    path: "../wit/http-status-probe.wit",
    world: "http-status-probe",
    with: {
        "wasi:http/types.response": Response,
    },
});

#[derive(Default)]
struct Stats {
    status_reads: u32,
    drops: u32,
}

struct State {
    table: ResourceTable,
    stats: Stats,
}

impl wasi::http::types::Host for State {}

impl wasi::http::types::HostResponse for State {
    fn get_status_code(&mut self, response: Resource<Response>) -> u16 {
        self.stats.status_reads += 1;
        self.table
            .get(&response)
            .expect("response handle must be valid");
        27_815
    }

    fn drop(&mut self, response: Resource<Response>) -> wasmtime::Result<()> {
        self.table.delete(response)?;
        self.stats.drops += 1;
        Ok(())
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-http-response-status-host-runner <component.wasm>")?;
    run(Path::new(&component_path))
}

fn run(component_path: &Path) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    map_wasmtime(wasi::http::types::add_to_linker::<State, HasSelf<State>>(
        &mut linker,
        |state| state,
    ))?;

    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Stats::default(),
        },
    );
    let response = store.data_mut().table.push(Response)?;
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let probe = instance
        .get_export_index(&mut store, None, HTTP_PROBE_INSTANCE)
        .context("missing wasi:http/probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing wasi:http/probe.run export")?;
    let run =
        map_wasmtime(instance.get_typed_func::<(Resource<Response>,), (u16,)>(&mut store, &run))?;
    let (status,) = map_wasmtime(run.call(&mut store, (response,)))?;
    if status != 27_815 {
        bail!("expected status 27815, got {status}");
    }
    if store.data().stats.status_reads != 1
        || store.data().stats.drops != 1
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected response stats: reads={} drops={} table_empty={}",
            store.data().stats.status_reads,
            store.data().stats.drops,
            store.data().table.is_empty(),
        );
    }

    println!("Rust P3 HTTP response status adapter passed");
    println!("status={status}");
    println!("drop={}", store.data().stats.drops);
    Ok(())
}
