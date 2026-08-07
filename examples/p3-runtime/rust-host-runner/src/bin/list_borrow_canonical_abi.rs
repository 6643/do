use anyhow::{Context, Result, bail};
use std::path::Path;
use wasmtime::component::{Component, Linker, Resource, ResourceTable, ResourceType};
use wasmtime::{Config, Engine, Store};

const API_INSTANCE: &str = "do:list-borrow-canonical/api@0.1.0";
const LIST_POINTER: u32 = 64;
const LIST_ELEMENT_STRIDE: u32 = 4;

struct Ticket {
    value: u32,
}

#[derive(Default)]
struct Stats {
    values: Vec<u32>,
    borrow_calls: u32,
    owner_drops: u32,
}

struct State {
    table: ResourceTable,
    stats: Stats,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn parse_mode(value: &str) -> Result<u32> {
    let mode = value
        .parse::<u32>()
        .with_context(|| format!("mode must be 0, 1, or 3 (got {value})"))?;
    if matches!(mode, 0 | 1 | 3) {
        Ok(mode)
    } else {
        bail!("mode must be 0, 1, or 3 (got {mode})")
    }
}

fn format_values(values: &[u32]) -> String {
    let body = values
        .iter()
        .map(u32::to_string)
        .collect::<Vec<_>>()
        .join(",");
    format!("[{body}]")
}

fn run(component_path: &Path, mode: u32) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;

    let mut linker: Linker<State> = Linker::new(&engine);
    let mut api = map_wasmtime(linker.instance(API_INSTANCE))?;
    map_wasmtime(api.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        |mut store, rep| {
            let state = store.data_mut();
            state.stats.owner_drops += 1;
            let _ = state.table.delete(Resource::<Ticket>::new_own(rep))?;
            Ok(())
        },
    ))?;
    map_wasmtime(
        api.func_wrap("read", |mut store, (values,): (Vec<Resource<Ticket>>,)| {
            let state = store.data_mut();
            if state.stats.owner_drops != 0 {
                return Err(wasmtime::Error::msg(
                    "owner was dropped before borrow callback",
                ));
            }
            let mut observed = Vec::with_capacity(values.len());
            for value in &values {
                observed.push(state.table.get(value)?.value);
            }
            state.stats.borrow_calls += 1;
            state.stats.values = observed;
            Ok((111u32,))
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
    let ticket = store.data_mut().table.push(Ticket { value: 111 })?;
    let run = map_wasmtime(
        instance.get_typed_func::<(Resource<Ticket>, u32), (u32,)>(&mut store, "run"),
    )?;
    let (result,) = map_wasmtime(run.call(&mut store, (ticket, mode)))?;
    if result != 111 {
        bail!("expected read result 111, got {result}");
    }

    let stats = &store.data().stats;
    let expected_values = match mode {
        0 => Vec::new(),
        1 => vec![111],
        3 => vec![111, 111, 111],
        _ => unreachable!(),
    };
    if stats.values != expected_values
        || stats.borrow_calls != 1
        || stats.owner_drops != 1
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected list borrow stats: mode={mode} values={:?} borrow-calls={} owner-drops={} table-empty={}",
            stats.values,
            stats.borrow_calls,
            stats.owner_drops,
            store.data().table.is_empty(),
        );
    }
    println!(
        "mode={mode} values={} borrow-calls={} owner-drops={} table-empty=true observed-list-pointer={} observed-list-element-stride={}",
        format_values(&stats.values),
        stats.borrow_calls,
        stats.owner_drops,
        LIST_POINTER,
        LIST_ELEMENT_STRIDE,
    );
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: do-p3-list-borrow-canonical-abi <component.wasm> <mode>")?;
    let mode = parse_mode(
        &args
            .next()
            .context("usage: do-p3-list-borrow-canonical-abi <component.wasm> <mode>")?,
    )?;
    if args.next().is_some() {
        bail!("usage: do-p3-list-borrow-canonical-abi <component.wasm> <mode>");
    }
    run(Path::new(&component_path), mode)
}
