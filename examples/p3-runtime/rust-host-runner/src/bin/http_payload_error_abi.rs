use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Accessor, AccessorTask, Component, FutureReader, Linker, Resource, ResourceTable, ResourceType,
    StreamReader,
};
use wasmtime::{Config, Engine, Store};

const HTTP_TYPES_INSTANCE: &str = "wasi:http/types@0.3.0-rc-2025-09-16";
const HTTP_CLIENT_INSTANCE: &str = "wasi:http/client@0.3.0-rc-2025-09-16";
const HTTP_PROBE_INSTANCE: &str = "wasi:http/probe@0.3.0-rc-2025-09-16";
const HTTP_HANDLER_INSTANCE: &str = "wasi:http/handler@0.3.0-rc-2025-09-16";

pub struct Request;
pub struct Fields;
pub struct RequestOptions;
pub struct Response;

// Use the complete pinned WIT package so the generated ErrorCode type keeps
// every case, including the payload variants under test.
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

struct State {
    table: ResourceTable,
    stats: Stats,
}

#[derive(Default)]
struct Stats {
    request_consumed: u32,
    response_created: u32,
    response_dropped: u32,
}

struct TransmissionCompletion;

impl Future for TransmissionCompletion {
    type Output = wasmtime::Result<std::result::Result<(), wasi::http::types::ErrorCode>>;

    fn poll(self: Pin<&mut Self>, _cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        Poll::Ready(Ok(Ok(())))
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
                "HTTP payload probe wake was dropped",
            ))),
        }
    }
}

struct HostWake {
    completion: oneshot::Sender<()>,
}

#[derive(Clone, Copy)]
enum ProbeCase {
    DnsTimeout,
    InternalErrorNone,
    InternalErrorSome,
    DnsError,
}

#[derive(Clone, Copy)]
enum Delivery {
    Pending,
    Ready,
}

impl Delivery {
    fn parse(name: &str) -> Result<Self> {
        match name {
            "pending" => Ok(Self::Pending),
            "ready" => Ok(Self::Ready),
            other => bail!("unknown delivery mode `{other}`"),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Ready => "ready",
        }
    }
}

impl ProbeCase {
    fn parse(name: &str) -> Result<Self> {
        match name {
            "dns-timeout" => Ok(Self::DnsTimeout),
            "internal-error-none" => Ok(Self::InternalErrorNone),
            "internal-error-some" => Ok(Self::InternalErrorSome),
            "dns-error" => Ok(Self::DnsError),
            other => bail!("unknown payload probe case `{other}`"),
        }
    }
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
        .context("usage: do-p3-http-payload-error-abi-host-runner <component.wasm>")?;
    let candidate = std::env::args()
        .nth(2)
        .unwrap_or_else(|| "unknown".to_owned());
    let case_name = std::env::args()
        .nth(3)
        .unwrap_or_else(|| "internal-error-some".to_owned());
    let delivery = Delivery::parse(
        &std::env::args()
            .nth(4)
            .unwrap_or_else(|| "pending".to_owned()),
    )?;
    let case = ProbeCase::parse(&case_name)?;
    futures::executor::block_on(run(
        Path::new(&component_path),
        &candidate,
        &case_name,
        case,
        delivery,
    ))
}

async fn run(
    component_path: &Path,
    candidate: &str,
    case_name: &str,
    case: ProbeCase,
    delivery: Delivery,
) -> Result<()> {
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
        "fields",
        ResourceType::host::<Fields>(),
        |mut store, rep| {
            store
                .data_mut()
                .table
                .delete(Resource::<Fields>::new_own(rep))?;
            Ok(())
        },
    ))?;
    map_wasmtime(types.resource(
        "request",
        ResourceType::host::<Request>(),
        |mut store, rep| {
            store
                .data_mut()
                .table
                .delete(Resource::<Request>::new_own(rep))?;
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
        |mut store, rep| {
            let state = store.data_mut();
            state.table.delete(Resource::<Response>::new_own(rep))?;
            state.stats.response_dropped += 1;
            Ok(())
        },
    ))?;

    map_wasmtime(types.func_wrap("[constructor]fields", |mut store, ()| {
        let fields = store.data_mut().table.push(Fields)?;
        Ok((fields,))
    }))?;
    map_wasmtime(types.func_wrap(
        "[static]request.new",
        |mut store,
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
                    "payload error probe request unexpectedly has a body",
                ));
            }
            if options.is_some() {
                return Err(wasmtime::Error::msg(
                    "payload error probe request unexpectedly has options",
                ));
            }
            trailers.close(&mut store)?;
            store.data_mut().table.delete(headers)?;
            let request = store.data_mut().table.push(Request)?;
            let transmission = FutureReader::new(&mut store, TransmissionCompletion)?;
            Ok(((request, transmission),))
        },
    ))?;

    let mut client = map_wasmtime(linker.instance(HTTP_CLIENT_INSTANCE))?;
    map_wasmtime(client.func_wrap_concurrent(
        "send",
        move |accessor, (request,): (Resource<Request>,)| {
            let consumed = accessor.with(|mut access| {
                let state = access.data_mut();
                state.table.delete(request)?;
                state.stats.request_consumed += 1;
                Ok::<(), wasmtime::Error>(())
            });
            if let Err(error) = consumed {
                return Box::pin(async move {
                    Err(wasmtime::Error::msg(format!(
                        "request consume failed: {error}"
                    )))
                });
            }
            let host_event = match delivery {
                Delivery::Pending => {
                    let (completion_sender, completion) = oneshot::channel();
                    Some((
                        accessor.spawn(HostWake {
                            completion: completion_sender,
                        }),
                        completion,
                    ))
                }
                Delivery::Ready => None,
            };
            Box::pin(async move {
                if let Some((host_event, completion)) = host_event {
                    host_event?;
                    PendingCompletion { completion }.await?;
                }
                let error = match case {
                    ProbeCase::DnsTimeout => wasi::http::types::ErrorCode::DnsTimeout,
                    ProbeCase::InternalErrorNone => {
                        wasi::http::types::ErrorCode::InternalError(None)
                    }
                    ProbeCase::InternalErrorSome => {
                        wasi::http::types::ErrorCode::InternalError(Some("x".to_owned()))
                    }
                    ProbeCase::DnsError => {
                        wasi::http::types::ErrorCode::DnsError(wasi::http::types::DnsErrorPayload {
                            rcode: Some("EAI".to_owned()),
                            info_code: Some(7),
                        })
                    }
                };
                Ok::<
                    (std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>,),
                    wasmtime::Error,
                >((Err(error),))
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
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    if candidate == "compiler-service" {
        return run_compiler_service(&mut store, &instance, case_name, case, delivery).await;
    }
    if candidate == "service-probe" {
        return run_service_probe(&mut store, &instance, case_name, case, delivery).await;
    }
    let probe = instance
        .get_export_index(&mut store, None, HTTP_PROBE_INSTANCE)
        .context("missing wasi:http/probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing wasi:http/probe.run export")?;
    let run = map_wasmtime(instance.get_typed_func::<(), (
        std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>,
    )>(&mut store, &run))?;

    let outer = store
        .run_concurrent(async |accessor| run.call_concurrent(accessor, ()).await)
        .await;
    let inner = match outer {
        Ok(value) => value,
        Err(error) => {
            println!(
                "payload-gate=blocked candidate={candidate} case={case_name} observation=trap:{error:#}"
            );
            println!("table-empty={}", store.data().table.is_empty());
            return Ok(());
        }
    };
    let result = match inner {
        Ok(value) => value,
        Err(error) => {
            println!(
                "payload-gate=blocked candidate={candidate} case={case_name} observation=trap:{error:#}"
            );
            println!("table-empty={}", store.data().table.is_empty());
            return Ok(());
        }
    };

    let (status, observation) = match (case, result.0) {
        (ProbeCase::DnsTimeout, Err(wasi::http::types::ErrorCode::DnsTimeout)) => {
            ("green", "DNS-timeout".to_owned())
        }
        (ProbeCase::InternalErrorNone, Err(wasi::http::types::ErrorCode::InternalError(None))) => {
            ("green", "InternalError(None)".to_owned())
        }
        (
            ProbeCase::InternalErrorSome,
            Err(wasi::http::types::ErrorCode::InternalError(Some(value))),
        ) if value == "x" => ("green", "InternalError(Some(\"x\"))".to_owned()),
        (ProbeCase::DnsError, Err(wasi::http::types::ErrorCode::DnsError(payload)))
            if payload.rcode.as_deref() == Some("EAI") && payload.info_code == Some(7) =>
        {
            (
                "green",
                "DnsError(rcode=Some(\"EAI\"),info-code=Some(7))".to_owned(),
            )
        }
        (_, Err(wasi::http::types::ErrorCode::InternalError(value))) => {
            ("blocked", format!("InternalError({value:?})"))
        }
        (_, Err(wasi::http::types::ErrorCode::DnsError(payload))) => (
            "blocked",
            format!(
                "DnsError(rcode={:?},info-code={:?})",
                payload.rcode, payload.info_code
            ),
        ),
        (_, other) => ("blocked", format!("{other:?}")),
    };
    println!(
        "payload-gate={status} candidate={candidate} case={case_name} observation={observation}"
    );
    println!("table-empty={}", store.data().table.is_empty());
    if !store.data().table.is_empty() {
        bail!("payload probe leaked a resource");
    }
    Ok(())
}

async fn run_compiler_service(
    store: &mut Store<State>,
    instance: &wasmtime::component::Instance,
    case_name: &str,
    case: ProbeCase,
    delivery: Delivery,
) -> Result<()> {
    let handler = instance
        .get_export_index(&mut *store, None, HTTP_HANDLER_INSTANCE)
        .context("missing wasi:http/handler export")?;
    let handle = instance
        .get_export_index(&mut *store, Some(&handler), "handle")
        .context("missing wasi:http/handler.handle export")?;
    let handle = map_wasmtime(instance.get_typed_func::<(Resource<Request>,), (
        std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>,
    )>(&mut *store, &handle))?;
    let request = store.data_mut().table.push(Request)?;
    let outer = store
        .run_concurrent(async |accessor| handle.call_concurrent(accessor, (request,)).await)
        .await;
    let result = map_wasmtime(map_wasmtime(outer)?)?;
    let observation = match (case, result.0) {
        (ProbeCase::InternalErrorNone, Err(wasi::http::types::ErrorCode::InternalError(None))) => {
            "InternalError(None)".to_owned()
        }
        (
            ProbeCase::InternalErrorSome,
            Err(wasi::http::types::ErrorCode::InternalError(Some(value))),
        ) if value == "x" => "InternalError(Some(\"x\"))".to_owned(),
        (ProbeCase::DnsError, Err(wasi::http::types::ErrorCode::DnsError(payload)))
            if payload.rcode.as_deref() == Some("EAI") && payload.info_code == Some(7) =>
        {
            "DnsError(rcode=Some(\"EAI\"),info-code=Some(7))".to_owned()
        }
        (_, Err(error)) => bail!("compiler service returned unexpected {error:?} for {case_name}"),
        (_, Ok(response)) => {
            let _ = store.data_mut().table.delete(response)?;
            store.data_mut().stats.response_dropped += 1;
            bail!("compiler service unexpectedly returned a response for {case_name}")
        }
    };

    let stats = &store.data().stats;
    if stats.request_consumed != 1
        || stats.response_created != 0
        || stats.response_dropped != 0
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected compiler service stats: consumed={} created={} dropped={} table-empty={}",
            stats.request_consumed,
            stats.response_created,
            stats.response_dropped,
            store.data().table.is_empty(),
        );
    }
    println!(
        "compiler-gate=green delivery={} case={} observation={}",
        delivery.name(),
        case_name,
        observation
    );
    println!("request-consumed={}", stats.request_consumed);
    println!("response-created={}", stats.response_created);
    println!("table-empty={}", store.data().table.is_empty());
    Ok(())
}

async fn run_service_probe(
    store: &mut Store<State>,
    instance: &wasmtime::component::Instance,
    case_name: &str,
    case: ProbeCase,
    delivery: Delivery,
) -> Result<()> {
    let handler = instance
        .get_export_index(&mut *store, None, HTTP_HANDLER_INSTANCE)
        .context("missing wasi:http/handler export")?;
    let handle = instance
        .get_export_index(&mut *store, Some(&handler), "handle")
        .context("missing wasi:http/handler.handle export")?;
    let handle = map_wasmtime(instance.get_typed_func::<(Resource<Request>,), (
        std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>,
    )>(&mut *store, &handle))?;
    let request = store.data_mut().table.push(Request)?;
    let request_for_cleanup = Resource::<Request>::new_own(request.rep());
    let outer = store
        .run_concurrent(async |accessor| handle.call_concurrent(accessor, (request,)).await)
        .await;
    let result = map_wasmtime(map_wasmtime(outer)?)?;
    let observation = match (case, result.0) {
        (ProbeCase::DnsTimeout, Err(wasi::http::types::ErrorCode::DnsTimeout)) => {
            "DNS-timeout".to_owned()
        }
        (ProbeCase::InternalErrorNone, Err(wasi::http::types::ErrorCode::InternalError(None))) => {
            "InternalError(None)".to_owned()
        }
        (
            ProbeCase::InternalErrorSome,
            Err(wasi::http::types::ErrorCode::InternalError(Some(value))),
        ) if value == "x" => "InternalError(Some(\"x\"))".to_owned(),
        (ProbeCase::DnsError, Err(wasi::http::types::ErrorCode::DnsError(payload)))
            if payload.rcode.as_deref() == Some("EAI") && payload.info_code == Some(7) =>
        {
            "DnsError(rcode=Some(\"EAI\"),info-code=Some(7))".to_owned()
        }
        (_, Err(error)) => bail!("service probe returned unexpected {error:?} for {case_name}"),
        (_, Ok(response)) => {
            let _ = store.data_mut().table.delete(response)?;
            store.data_mut().stats.response_dropped += 1;
            bail!("service probe unexpectedly returned a response for {case_name}");
        }
    };

    if store.data().table.get(&request_for_cleanup).is_ok() {
        store.data_mut().table.delete(request_for_cleanup)?;
    }
    let stats = &store.data().stats;
    if !store.data().table.is_empty() {
        bail!(
            "service probe leaked a resource: consumed={} created={} dropped={}",
            stats.request_consumed,
            stats.response_created,
            stats.response_dropped,
        );
    }
    println!(
        "service-probe-gate=green delivery={} case={} observation={}",
        delivery.name(),
        case_name,
        observation
    );
    println!("request-consumed={}", stats.request_consumed);
    println!("response-created={}", stats.response_created);
    println!("table-empty={}", store.data().table.is_empty());
    Ok(())
}
