use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Accessor, AccessorTask, Component, Linker, Resource, ResourceTable, ResourceType,
};
use wasmtime::{Config, Engine, Store};

const HTTP_TYPES_INSTANCE: &str = "wasi:http/types@0.3.0-rc-2025-09-16";
const HTTP_CLIENT_INSTANCE: &str = "wasi:http/client@0.3.0-rc-2025-09-16";
const HTTP_HANDLER_INSTANCE: &str = "wasi:http/handler@0.3.0-rc-2025-09-16";

pub struct Request;
pub struct Response;

wasmtime::component::bindgen!({
    path: "../../../src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16",
    world: "service",
    imports: { default: async | trappable },
    exports: { default: async },
    with: {
        "wasi:http/types.request": Request,
        "wasi:http/types.response": Response,
    },
});

#[derive(Default)]
struct Stats {
    request_consumed: u32,
    response_created: u32,
    response_dropped: u32,
}

struct State {
    table: ResourceTable,
    stats: Stats,
}

struct PendingCompletion {
    completion: oneshot::Receiver<()>,
}

impl Future for PendingCompletion {
    type Output = wasmtime::Result<()>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        match Pin::new(&mut self.completion).poll(cx) {
            Poll::Pending => Poll::Pending,
            Poll::Ready(Ok(())) => Poll::Ready(Ok(())),
            Poll::Ready(Err(_)) => Poll::Ready(Err(wasmtime::Error::msg(
                "HTTP completion wake was dropped",
            ))),
        }
    }
}

struct HostWake {
    completion: oneshot::Sender<()>,
}

impl AccessorTask<State> for HostWake {
    fn run(self, _accessor: &Accessor<State>) -> impl Future<Output = wasmtime::Result<()>> + Send {
        async move {
            let _ = self.completion.send(());
            Ok(())
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-http-service-host-runner <component.wasm>")?;
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
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut types = map_wasmtime(linker.instance(HTTP_TYPES_INSTANCE))?;
    map_wasmtime(types.resource(
        "request",
        ResourceType::host::<Request>(),
        |mut store, rep| {
            let state = store.data_mut();
            let _ = state.table.delete(Resource::<Request>::new_own(rep))?;
            Ok(())
        },
    ))?;
    map_wasmtime(types.resource(
        "response",
        ResourceType::host::<Response>(),
        |mut store, rep| {
            let state = store.data_mut();
            let _ = state.table.delete(Resource::<Response>::new_own(rep))?;
            state.stats.response_dropped += 1;
            Ok(())
        },
    ))?;

    let completion_count = Arc::new(Mutex::new(0_u32));
    let host_completions = Arc::clone(&completion_count);
    let mut client = map_wasmtime(linker.instance(HTTP_CLIENT_INSTANCE))?;
    map_wasmtime(client.func_wrap_concurrent(
        "send",
        move |accessor, (request,): (Resource<Request>,)| {
            let response_or_error = accessor.with(|mut access| {
                let state = access.data_mut();
                let _ = state.table.delete(request)?;
                state.stats.request_consumed += 1;
                Ok::<bool, wasmtime::Error>(state.stats.request_consumed == 2)
            });
            let emit_error = match response_or_error {
                Ok(value) => value,
                Err(error) => return Box::pin(async move { Err(error) }),
            };
            let (completion_sender, completion) = oneshot::channel();
            let host_completions = Arc::clone(&host_completions);
            let host_event = accessor.spawn(HostWake {
                completion: completion_sender,
            });
            Box::pin(async move {
                host_event?;
                PendingCompletion { completion }.await?;
                *host_completions
                    .lock()
                    .expect("HTTP completion counter mutex poisoned") += 1;
                if emit_error {
                    return Ok::<
                        (std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>,),
                        wasmtime::Error,
                    >((Err(wasi::http::types::ErrorCode::DnsTimeout),));
                }
                let response = accessor.with(|mut access| {
                    let state = access.data_mut();
                    let response = state.table.push(Response)?;
                    state.stats.response_created += 1;
                    Ok::<Resource<Response>, wasmtime::Error>(response)
                })?;
                Ok::<
                    (std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>,),
                    wasmtime::Error,
                >((Ok(response),))
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
    let first_request = store.data_mut().table.push(Request)?;
    let second_request = store.data_mut().table.push(Request)?;
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let handler = instance
        .get_export_index(&mut store, None, HTTP_HANDLER_INSTANCE)
        .context("missing wasi:http/handler export")?;
    let handle = instance
        .get_export_index(&mut store, Some(&handler), "handle")
        .context("missing wasi:http/handler.handle export")?;
    let handle = map_wasmtime(instance.get_typed_func::<(Resource<Request>,), (
        std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>,
    )>(&mut store, &handle))?;
    let results = map_wasmtime(map_wasmtime(
        store
            .run_concurrent(async |accessor| {
                futures::try_join!(
                    handle.call_concurrent(accessor, (first_request,)),
                    handle.call_concurrent(accessor, (second_request,)),
                )
            })
            .await,
    )?)?;

    let first_response = results
        .0
        .0
        .map_err(|error| anyhow::anyhow!("expected Ok(response), got {error:?}"))?;
    if !first_response.owned() {
        bail!("expected returned response to be owned by the caller");
    }
    let _ = store.data_mut().table.delete(first_response)?;
    store.data_mut().stats.response_dropped += 1;
    match results.1.0 {
        Err(wasi::http::types::ErrorCode::DnsTimeout) => {}
        other => bail!("expected Err(DnsTimeout), got {other:?}"),
    }

    let stats = &store.data().stats;
    let completions = *completion_count
        .lock()
        .expect("HTTP completion counter mutex poisoned");
    if stats.request_consumed != 2
        || stats.response_created != 1
        || stats.response_dropped != 1
        || completions != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected HTTP service stats: consumed={} created={} dropped={} completions={}",
            stats.request_consumed,
            stats.response_created,
            stats.response_dropped,
            completions,
        );
    }

    println!("Rust P3 HTTP service adapter passed");
    Ok(())
}
