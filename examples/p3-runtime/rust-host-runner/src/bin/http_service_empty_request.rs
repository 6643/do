use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Accessor, AccessorTask, Component, FutureReader, Linker, Resource, ResourceTable, ResourceType,
    StreamReader,
};
use wasmtime::{Config, Engine, Store};

const HTTP_TYPES_INSTANCE: &str = "wasi:http/types@0.3.0-rc-2025-09-16";
const HTTP_CLIENT_INSTANCE: &str = "wasi:http/client@0.3.0-rc-2025-09-16";
const HTTP_PROBE_INSTANCE: &str = "wasi:http/probe@0.3.0-rc-2025-09-16";

pub struct Fields;
pub struct Request;
pub struct RequestOptions;
pub struct Response;

wasmtime::component::bindgen!({
    path: "../../../src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16",
    world: "service",
    imports: { default: async | trappable },
    exports: { default: async },
    with: {
        "wasi:http/types.fields": Fields,
        "wasi:http/types.request": Request,
        "wasi:http/types.request-options": RequestOptions,
        "wasi:http/types.response": Response,
    },
});

#[derive(Default)]
struct Stats {
    requests: u32,
    request_drops: u32,
    responses: u32,
    response_drops: u32,
    fields_drops: u32,
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
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-http-service-empty-request-host-runner <component.wasm>")?;
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

    let fields_stats = Arc::clone(&stats);
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
            let _ = &fields_stats;
            Ok(())
        },
    ))?;
    let request_stats = Arc::clone(&stats);
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
            let _ = &request_stats;
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
    map_wasmtime(types.resource(
        "response",
        ResourceType::host::<Response>(),
        move |mut store, rep| {
            let state = store.data_mut();
            state.table.delete(Resource::<Response>::new_own(rep))?;
            state
                .stats
                .lock()
                .expect("response stats mutex poisoned")
                .response_drops += 1;
            Ok(())
        },
    ))?;

    let constructor_stats = Arc::clone(&stats);
    map_wasmtime(
        types.func_wrap("[constructor]fields", move |mut store, ()| {
            let fields = store.data_mut().table.push(Fields)?;
            let _ = &constructor_stats;
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
                state
                    .stats
                    .lock()
                    .expect("request constructor stats mutex poisoned")
                    .fields_drops += 1;
                state
                    .stats
                    .lock()
                    .expect("trailers stats mutex poisoned")
                    .trailers_future_drops += 1;
            }
            let request = store.data_mut().table.push(Request)?;
            let transmission = FutureReader::new(
                &mut store,
                TransmissionCompletion {
                    stats: Arc::clone(&transmission_stats),
                },
            )?;
            Ok(((request, transmission),))
        },
    ))?;

    let completion_count = Arc::new(Mutex::new(0_u32));
    let host_completions = Arc::clone(&completion_count);
    let mut client = map_wasmtime(linker.instance(HTTP_CLIENT_INSTANCE))?;
    map_wasmtime(client.func_wrap_concurrent(
        "send",
        move |accessor, (request,): (Resource<Request>,)| {
            let emit_error = accessor.with(|mut access| {
                let state = access.data_mut();
                state.table.delete(request)?;
                let mut stats = state
                    .stats
                    .lock()
                    .expect("request send stats mutex poisoned");
                stats.requests += 1;
                Ok::<bool, wasmtime::Error>(stats.requests == 2)
            });
            let emit_error = match emit_error {
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
                    state
                        .stats
                        .lock()
                        .expect("response stats mutex poisoned")
                        .responses += 1;
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
    let run = map_wasmtime(instance.get_typed_func::<(), (
        std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>,
    )>(&mut store, &run))?;

    let first = {
        let call = map_wasmtime(
            store
                .run_concurrent(async |accessor| run.call_concurrent(accessor, ()).await)
                .await,
        )?;
        map_wasmtime(call)?
    };
    let first_response = first
        .0
        .map_err(|error| anyhow::anyhow!("expected first Ok(response), got {error:?}"))?;
    store.data_mut().table.delete(first_response)?;
    store
        .data()
        .stats
        .lock()
        .expect("response stats mutex poisoned")
        .response_drops += 1;

    let second = {
        let call = map_wasmtime(
            store
                .run_concurrent(async |accessor| run.call_concurrent(accessor, ()).await)
                .await,
        )?;
        map_wasmtime(call)?
    };
    match second.0 {
        Err(wasi::http::types::ErrorCode::DnsTimeout) => {}
        other => bail!("expected second Err(DnsTimeout), got {other:?}"),
    }

    let stats = stats.lock().expect("request stats mutex poisoned");
    let completions = *completion_count
        .lock()
        .expect("HTTP completion counter mutex poisoned");
    if stats.requests != 2
        || stats.request_drops != 0
        || stats.responses != 1
        || stats.response_drops != 1
        || stats.fields_drops != 2
        || stats.transmission_future_drops != 2
        || stats.trailers_future_drops != 2
        || completions != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected empty request service stats: requests={} request-drops={} responses={} response-drops={} fields-drops={} transmission-future-drops={} trailers-future-drops={} completions={} table-empty={}",
            stats.requests,
            stats.request_drops,
            stats.responses,
            stats.response_drops,
            stats.fields_drops,
            stats.transmission_future_drops,
            stats.trailers_future_drops,
            completions,
            store.data().table.is_empty(),
        );
    }

    println!("Rust P3 HTTP empty request service adapter passed");
    println!("requests={}", stats.requests);
    println!("responses={}", stats.responses);
    println!("request-drops={}", stats.request_drops);
    println!("response-drops={}", stats.response_drops);
    println!(
        "transmission-future-drops={}",
        stats.transmission_future_drops
    );
    println!("trailers-future-drops={}", stats.trailers_future_drops);
    println!("table-empty={}", store.data().table.is_empty());
    Ok(())
}
