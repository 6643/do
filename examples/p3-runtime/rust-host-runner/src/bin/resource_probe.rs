use anyhow::{Context, Result, bail};
use std::path::Path;
use wasmtime::component::{Component, Linker, Resource, ResourceTable, ResourceType};
use wasmtime::{Config, Engine, Store};

pub struct Ticket {
    value: u32,
}

#[derive(Default)]
struct Stats {
    create: u32,
    borrow: u32,
    consume: u32,
    drop: u32,
}

struct State {
    table: ResourceTable,
    stats: Stats,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-resource-probe-host-runner <component.wasm>")?;
    run(Path::new(&component_path))
}

fn run(component_path: &Path) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut ledger = map_wasmtime(linker.instance("do:resource-probe/ledger@0.1.0"))?;
    map_wasmtime(ledger.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            let _ = state.table.delete(Resource::<Ticket>::new_own(rep))?;
            state.stats.drop += 1;
            Ok(())
        },
    ))?;
    map_wasmtime(ledger.func_wrap("create", |mut store, (seed,): (u32,)| {
        let state = store.data_mut();
        state.stats.create += 1;
        Ok((state.table.push(Ticket { value: seed })?,))
    }))?;
    map_wasmtime(ledger.func_wrap(
        "borrow-value",
        |mut store, (ticket,): (Resource<Ticket>,)| {
            let state = store.data_mut();
            state.stats.borrow += 1;
            Ok((state.table.get(&ticket)?.value,))
        },
    ))?;
    map_wasmtime(
        ledger.func_wrap("consume", |mut store, (ticket,): (Resource<Ticket>,)| {
            let state = store.data_mut();
            state.stats.consume += 1;
            Ok((state.table.delete(ticket)?.value,))
        }),
    )?;

    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Stats::default(),
        },
    );
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(u32,), (u32,)>(&mut store, "run"))?;
    let (result,) = map_wasmtime(run.call(&mut store, (27_815,)))?;
    if result != 27_815 {
        bail!("expected resource probe result 27815, got {result}");
    }
    if store.data().stats.create != 2
        || store.data().stats.borrow != 2
        || store.data().stats.consume != 1
        || store.data().stats.drop != 1
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected ticket stats: create={} borrow={} consume={} drop={}",
            store.data().stats.create,
            store.data().stats.borrow,
            store.data().stats.consume,
            store.data().stats.drop,
        );
    }
    println!("Rust P3 resource adapter passed");
    println!("ticket create={}", store.data().stats.create);
    println!("ticket borrow={}", store.data().stats.borrow);
    println!("ticket consume={}", store.data().stats.consume);
    println!("ticket drop={}", store.data().stats.drop);
    Ok(())
}
