use anyhow::{Context, Result, bail};
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{Component, Linker, Resource, ResourceTable, ResourceType};
use wasmtime::{Config, Engine, Store};

const HTTP_INSTANCE: &str = "do:resource-probe-owned-error/http@0.1.0";

pub struct Request;
pub struct Response;
pub struct ErrorResource;

wasmtime::component::bindgen!({
    inline: r#"
        package probe:owned-error-cancel-types@0.1.0;

        interface http {
          resource request {}
          resource response {}
          resource error-resource {}

          send: async func(request: request) -> result<response, error-resource>;
        }

        world owned-error-resource-cancel-types {
          import http;
        }
    "#,
    world: "owned-error-resource-cancel-types",
    imports: { default: async | trappable },
    exports: { default: async },
    with: {
        "probe:owned-error-cancel-types/http.request": Request,
        "probe:owned-error-cancel-types/http.response": Response,
        "probe:owned-error-cancel-types/http.error-resource": ErrorResource,
    },
});

#[derive(Default)]
struct Stats {
    request_consumed: u32,
    response_created: u32,
    response_dropped: u32,
    error_created: u32,
    error_dropped: u32,
    pending_polls: u32,
    pending_drops: u32,
}

struct State {
    table: ResourceTable,
    stats: Stats,
}

struct PendingSend {
    stats: Arc<Mutex<Stats>>,
}

impl Future for PendingSend {
    type Output =
        wasmtime::Result<(std::result::Result<Resource<Response>, Resource<ErrorResource>>,)>;

    fn poll(self: Pin<&mut Self>, _cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        self.stats
            .lock()
            .expect("owned-error cancellation stats mutex poisoned")
            .pending_polls += 1;
        Poll::Pending
    }
}

impl Drop for PendingSend {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("owned-error cancellation stats mutex poisoned")
            .pending_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-owned-error-resource-cancel-host-runner <component.wasm>")?;
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
    let host_stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut http = map_wasmtime(linker.instance(HTTP_INSTANCE))?;

    map_wasmtime(http.resource(
        "request",
        ResourceType::host::<Request>(),
        |mut store, rep| {
            let state = store.data_mut();
            let _ = state.table.delete(Resource::<Request>::new_own(rep))?;
            Ok(())
        },
    ))?;
    map_wasmtime(http.resource(
        "response",
        ResourceType::host::<Response>(),
        |mut store, rep| {
            let state = store.data_mut();
            let _ = state.table.delete(Resource::<Response>::new_own(rep))?;
            state.stats.response_dropped += 1;
            Ok(())
        },
    ))?;
    map_wasmtime(http.resource(
        "error-resource",
        ResourceType::host::<ErrorResource>(),
        |mut store, rep| {
            let state = store.data_mut();
            let _ = state
                .table
                .delete(Resource::<ErrorResource>::new_own(rep))?;
            state.stats.error_dropped += 1;
            Ok(())
        },
    ))?;

    let send_stats = Arc::clone(&host_stats);
    map_wasmtime(http.func_wrap_concurrent(
        "send",
        move |accessor, (request,): (Resource<Request>,)| {
            let consumed = accessor.with(|mut access| {
                let state = access.data_mut();
                let _ = state.table.delete(request)?;
                state.stats.request_consumed += 1;
                Ok::<(), wasmtime::Error>(())
            });
            if let Err(error) = consumed {
                return Box::pin(async move { Err(error) });
            }
            Box::pin(PendingSend {
                stats: Arc::clone(&send_stats),
            })
        },
    ))?;

    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Stats::default(),
        },
    );
    let request = store.data_mut().table.push(Request)?;
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let cancel =
        map_wasmtime(instance.get_typed_func::<(Resource<Request>,), ()>(&mut store, "cancel"))?;
    map_wasmtime(map_wasmtime(
        store
            .run_concurrent(async |accessor| cancel.call_concurrent(accessor, (request,)).await)
            .await,
    )?)?;

    let host_stats = host_stats
        .lock()
        .expect("owned-error cancellation stats mutex poisoned");
    let stats = &store.data().stats;
    if stats.request_consumed != 1
        || stats.response_created != 0
        || stats.response_dropped != 0
        || stats.error_created != 0
        || stats.error_dropped != 0
        || host_stats.pending_polls == 0
        || host_stats.pending_drops != 1
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected owned-error cancellation stats: request-consumed={} response-created={} response-dropped={} error-created={} error-dropped={} pending-polls={} pending-future-drops={} table-empty={}",
            stats.request_consumed,
            stats.response_created,
            stats.response_dropped,
            stats.error_created,
            stats.error_dropped,
            host_stats.pending_polls,
            host_stats.pending_drops,
            store.data().table.is_empty(),
        );
    }

    println!("Rust P3 owned-error resource cancellation passed");
    println!("request consumed=1");
    println!("pending polls={}", host_stats.pending_polls);
    println!("pending future drops=1");
    println!("response create=0");
    println!("response drop=0");
    println!("error-resource create=0");
    println!("error-resource drop=0");
    println!("table-empty=true");
    Ok(())
}
