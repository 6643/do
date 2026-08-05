use anyhow::{Context, Result, bail};
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, FutureReader, Linker, Resource, ResourceTable, ResourceType, StreamReader,
};
use wasmtime::{Config, Engine, Store};

const HTTP_TYPES_INSTANCE: &str = "wasi:http/types@0.3.0-rc-2025-09-16";
const HTTP_PROBE_INSTANCE: &str = "wasi:http/probe@0.3.0-rc-2025-09-16";

pub struct Fields;
pub struct Request;
pub struct RequestOptions;

wasmtime::component::bindgen!({
    path: "../../../src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16",
    world: "service",
    imports: { default: async | trappable },
    exports: { default: async },
    with: {
        "wasi:http/types.fields": Fields,
        "wasi:http/types.request": Request,
        "wasi:http/types.request-options": RequestOptions,
    },
});

#[derive(Default)]
struct Stats {
    constructors: u32,
    fields_drops: u32,
    requests: u32,
    request_drops: u32,
    transmission_future_drops: u32,
    trailers_future_drops: u32,
}

struct State {
    table: ResourceTable,
    stats: Arc<Mutex<Stats>>,
}

struct TransmissionCompletion {
    stats: Arc<Mutex<Stats>>,
}

impl Future for TransmissionCompletion {
    type Output = wasmtime::Result<std::result::Result<(), wasi::http::types::ErrorCode>>;

    fn poll(self: Pin<&mut Self>, _cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        Poll::Ready(Ok(Ok(())))
    }
}

impl Drop for TransmissionCompletion {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("transmission future stats mutex poisoned")
            .transmission_future_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-http-request-new-host-runner <component.wasm>")?;
    futures::executor::block_on(run(Path::new(&component_path)))
}

async fn run(component_path: &Path) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.wasm_gc(true);
    config.concurrency_support(true);

    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut types = map_wasmtime(linker.instance(HTTP_TYPES_INSTANCE))?;

    map_wasmtime(types.resource(
        "fields",
        ResourceType::host::<Fields>(),
        move |mut store, rep| {
            let state = store.data_mut();
            state.table.delete(Resource::<Fields>::new_own(rep))?;
            state
                .stats
                .lock()
                .expect("fields stats mutex poisoned")
                .fields_drops += 1;
            Ok(())
        },
    ))?;
    map_wasmtime(types.resource(
        "request",
        ResourceType::host::<Request>(),
        move |mut store, rep| {
            let state = store.data_mut();
            state.table.delete(Resource::<Request>::new_own(rep))?;
            state
                .stats
                .lock()
                .expect("request stats mutex poisoned")
                .request_drops += 1;
            Ok(())
        },
    ))?;
    map_wasmtime(types.resource(
        "request-options",
        ResourceType::host::<RequestOptions>(),
        |mut store, rep| {
            store
                .data_mut()
                .table
                .delete(Resource::<RequestOptions>::new_own(rep))?;
            Ok(())
        },
    ))?;

    let constructor_stats = Arc::clone(&stats);
    map_wasmtime(
        types.func_wrap("[constructor]fields", move |mut store, ()| {
            let fields = store.data_mut().table.push(Fields)?;
            constructor_stats
                .lock()
                .expect("constructor stats mutex poisoned")
                .constructors += 1;
            Ok((fields,))
        }),
    )?;

    let transmission_stats = Arc::clone(&stats);
    map_wasmtime(types.func_wrap(
        "[static]request.new",
        move |mut store,
              (headers, contents, mut trailers, options): (
            Resource<Fields>,
            Option<StreamReader<u8>>,
            FutureReader<
                std::result::Result<Option<Resource<Fields>>, wasi::http::types::ErrorCode>,
            >,
            Option<Resource<RequestOptions>>,
        )| {
            if contents.is_some() {
                return Err(wasmtime::Error::msg(
                    "empty request constructor received a body stream",
                ));
            }
            if options.is_some() {
                return Err(wasmtime::Error::msg(
                    "empty request constructor received request options",
                ));
            }

            trailers.close(&mut store)?;
            {
                let state = store.data_mut();
                state.table.delete(headers)?;
                let mut stats = state
                    .stats
                    .lock()
                    .expect("request constructor stats mutex poisoned");
                stats.fields_drops += 1;
                stats.trailers_future_drops += 1;
            }

            let request = {
                let state = store.data_mut();
                let request = state.table.push(Request)?;
                state
                    .stats
                    .lock()
                    .expect("request stats mutex poisoned")
                    .requests += 1;
                request
            };
            let transmission = FutureReader::new(
                &mut store,
                TransmissionCompletion {
                    stats: Arc::clone(&transmission_stats),
                },
            )?;
            Ok(((request, transmission),))
        },
    ))?;

    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, HTTP_PROBE_INSTANCE)
        .context("missing wasi:http/probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing wasi:http/probe.run export")?;
    let run = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, &run))?;

    for _ in 0..2 {
        let call = map_wasmtime(
            store
                .run_concurrent(async |accessor| run.call_concurrent(accessor, ()).await)
                .await,
        )?;
        map_wasmtime(call)?;
    }

    let snapshot = stats.lock().expect("request stats mutex poisoned");
    if snapshot.constructors != 2
        || snapshot.fields_drops != 2
        || snapshot.requests != 2
        || snapshot.request_drops != 2
        || snapshot.transmission_future_drops != 2
        || snapshot.trailers_future_drops != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected request constructor stats: constructors={} fields-drops={} requests={} request-drops={} transmission-future-drops={} trailers-future-drops={} table-empty={}",
            snapshot.constructors,
            snapshot.fields_drops,
            snapshot.requests,
            snapshot.request_drops,
            snapshot.transmission_future_drops,
            snapshot.trailers_future_drops,
            store.data().table.is_empty(),
        );
    }

    println!("Rust P3 HTTP request constructor adapter passed");
    println!("constructors={}", snapshot.constructors);
    println!("fields-drops={}", snapshot.fields_drops);
    println!("requests={}", snapshot.requests);
    println!("request-drops={}", snapshot.request_drops);
    println!(
        "transmission-future-drops={}",
        snapshot.transmission_future_drops
    );
    println!("trailers-future-drops={}", snapshot.trailers_future_drops);
    println!("table-empty={}", store.data().table.is_empty());
    Ok(())
}
