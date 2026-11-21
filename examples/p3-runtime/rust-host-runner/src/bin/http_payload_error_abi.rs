use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    AccessorTask, Component, FutureReader, Linker, Resource, ResourceTable, ResourceType,
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
    DnsError,
    TlsAlertReceived,
    HttpRequestBodySize,
    HttpRequestHeaderSectionSize,
    HttpRequestHeaderSize,
    HttpRequestTrailerSectionSize,
    HttpRequestTrailerSize,
    HttpResponseHeaderSectionSize,
    HttpResponseHeaderSize,
    HttpResponseBodySize,
    HttpResponseTrailerSectionSize,
    HttpResponseTrailerSize,
    HttpResponseTransferCoding,
    HttpResponseContentCoding,
    InternalErrorNone,
    InternalErrorSome,
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
            "dns-error" => Ok(Self::DnsError),
            "tls-alert-received" => Ok(Self::TlsAlertReceived),
            "http-request-body-size" => Ok(Self::HttpRequestBodySize),
            "http-request-header-section-size" => Ok(Self::HttpRequestHeaderSectionSize),
            "http-request-header-size" => Ok(Self::HttpRequestHeaderSize),
            "http-request-trailer-section-size" => Ok(Self::HttpRequestTrailerSectionSize),
            "http-request-trailer-size" => Ok(Self::HttpRequestTrailerSize),
            "http-response-header-section-size" => Ok(Self::HttpResponseHeaderSectionSize),
            "http-response-header-size" => Ok(Self::HttpResponseHeaderSize),
            "http-response-body-size" => Ok(Self::HttpResponseBodySize),
            "http-response-trailer-section-size" => Ok(Self::HttpResponseTrailerSectionSize),
            "http-response-trailer-size" => Ok(Self::HttpResponseTrailerSize),
            "http-response-transfer-coding" => Ok(Self::HttpResponseTransferCoding),
            "http-response-content-coding" => Ok(Self::HttpResponseContentCoding),
            "internal-error-none" => Ok(Self::InternalErrorNone),
            "internal-error-some" => Ok(Self::InternalErrorSome),
            other => bail!("unknown payload probe case `{other}`"),
        }
    }
}

fn make_error(case: ProbeCase) -> wasi::http::types::ErrorCode {
    use wasi::http::types::{ErrorCode, FieldSizePayload, TlsAlertReceivedPayload};

    match case {
        ProbeCase::DnsTimeout => ErrorCode::DnsTimeout,
        ProbeCase::DnsError => ErrorCode::DnsError(wasi::http::types::DnsErrorPayload {
            rcode: Some("EAI".to_owned()),
            info_code: Some(7),
        }),
        ProbeCase::TlsAlertReceived => ErrorCode::TlsAlertReceived(TlsAlertReceivedPayload {
            alert_id: Some(42),
            alert_message: Some("alert".to_owned()),
        }),
        ProbeCase::HttpRequestBodySize => ErrorCode::HttpRequestBodySize(Some(1234)),
        ProbeCase::HttpRequestHeaderSectionSize => {
            ErrorCode::HttpRequestHeaderSectionSize(Some(123))
        }
        ProbeCase::HttpRequestHeaderSize => {
            ErrorCode::HttpRequestHeaderSize(Some(FieldSizePayload {
                field_name: Some("content-type".to_owned()),
                field_size: Some(42),
            }))
        }
        ProbeCase::HttpRequestTrailerSectionSize => {
            ErrorCode::HttpRequestTrailerSectionSize(Some(123))
        }
        ProbeCase::HttpRequestTrailerSize => ErrorCode::HttpRequestTrailerSize(FieldSizePayload {
            field_name: Some("content-type".to_owned()),
            field_size: Some(42),
        }),
        ProbeCase::HttpResponseHeaderSectionSize => {
            ErrorCode::HttpResponseHeaderSectionSize(Some(123))
        }
        ProbeCase::HttpResponseHeaderSize => ErrorCode::HttpResponseHeaderSize(FieldSizePayload {
            field_name: Some("content-type".to_owned()),
            field_size: Some(42),
        }),
        ProbeCase::HttpResponseBodySize => ErrorCode::HttpResponseBodySize(Some(1234)),
        ProbeCase::HttpResponseTrailerSectionSize => {
            ErrorCode::HttpResponseTrailerSectionSize(Some(123))
        }
        ProbeCase::HttpResponseTrailerSize => {
            ErrorCode::HttpResponseTrailerSize(FieldSizePayload {
                field_name: Some("content-type".to_owned()),
                field_size: Some(42),
            })
        }
        ProbeCase::HttpResponseTransferCoding => {
            ErrorCode::HttpResponseTransferCoding(Some("chunked".to_owned()))
        }
        ProbeCase::HttpResponseContentCoding => {
            ErrorCode::HttpResponseContentCoding(Some("gzip".to_owned()))
        }
        ProbeCase::InternalErrorNone => ErrorCode::InternalError(None),
        ProbeCase::InternalErrorSome => ErrorCode::InternalError(Some("x".to_owned())),
    }
}

fn observe_error(case: ProbeCase, error: wasi::http::types::ErrorCode) -> (&'static str, String) {
    use wasi::http::types::ErrorCode;

    match (case, error) {
        (ProbeCase::DnsTimeout, ErrorCode::DnsTimeout) => ("green", "DNS-timeout".to_owned()),
        (ProbeCase::DnsError, ErrorCode::DnsError(payload))
            if payload.rcode.as_deref() == Some("EAI") && payload.info_code == Some(7) =>
        {
            (
                "green",
                "DnsError(rcode=Some(\"EAI\"),info-code=Some(7))".to_owned(),
            )
        }
        (ProbeCase::TlsAlertReceived, ErrorCode::TlsAlertReceived(payload))
            if payload.alert_id == Some(42)
                && payload.alert_message.as_deref() == Some("alert") =>
        {
            (
                "green",
                "TlsAlertReceived(alert-id=Some(42),alert-message=Some(\"alert\"))".to_owned(),
            )
        }
        (ProbeCase::HttpRequestBodySize, ErrorCode::HttpRequestBodySize(Some(1234))) => {
            ("green", "HTTP-request-body-size(Some(1234))".to_owned())
        }
        (
            ProbeCase::HttpRequestHeaderSectionSize,
            ErrorCode::HttpRequestHeaderSectionSize(Some(123)),
        ) => (
            "green",
            "HTTP-request-header-section-size(Some(123))".to_owned(),
        ),
        (ProbeCase::HttpRequestHeaderSize, ErrorCode::HttpRequestHeaderSize(payload))
            if payload.as_ref().is_some_and(|payload| {
                payload.field_name.as_deref() == Some("content-type")
                    && payload.field_size == Some(42)
            }) =>
        {
            (
                "green",
                "HTTP-request-header-size(field-name=Some(\"content-type\"),field-size=Some(42))"
                    .to_owned(),
            )
        }
        (
            ProbeCase::HttpRequestTrailerSectionSize,
            ErrorCode::HttpRequestTrailerSectionSize(Some(123)),
        ) => (
            "green",
            "HTTP-request-trailer-section-size(Some(123))".to_owned(),
        ),
        (ProbeCase::HttpRequestTrailerSize, ErrorCode::HttpRequestTrailerSize(payload))
            if payload.field_name.as_deref() == Some("content-type")
                && payload.field_size == Some(42) =>
        {
            (
                "green",
                "HTTP-request-trailer-size(field-name=Some(\"content-type\"),field-size=Some(42))"
                    .to_owned(),
            )
        }
        (
            ProbeCase::HttpResponseHeaderSectionSize,
            ErrorCode::HttpResponseHeaderSectionSize(Some(123)),
        ) => (
            "green",
            "HTTP-response-header-section-size(Some(123))".to_owned(),
        ),
        (ProbeCase::HttpResponseHeaderSize, ErrorCode::HttpResponseHeaderSize(payload))
            if payload.field_name.as_deref() == Some("content-type")
                && payload.field_size == Some(42) =>
        {
            (
                "green",
                "HTTP-response-header-size(field-name=Some(\"content-type\"),field-size=Some(42))"
                    .to_owned(),
            )
        }
        (ProbeCase::HttpResponseBodySize, ErrorCode::HttpResponseBodySize(Some(1234))) => {
            ("green", "HTTP-response-body-size(Some(1234))".to_owned())
        }
        (
            ProbeCase::HttpResponseTrailerSectionSize,
            ErrorCode::HttpResponseTrailerSectionSize(Some(123)),
        ) => (
            "green",
            "HTTP-response-trailer-section-size(Some(123))".to_owned(),
        ),
        (ProbeCase::HttpResponseTrailerSize, ErrorCode::HttpResponseTrailerSize(payload))
            if payload.field_name.as_deref() == Some("content-type")
                && payload.field_size == Some(42) =>
        {
            (
                "green",
                "HTTP-response-trailer-size(field-name=Some(\"content-type\"),field-size=Some(42))"
                    .to_owned(),
            )
        }
        (
            ProbeCase::HttpResponseTransferCoding,
            ErrorCode::HttpResponseTransferCoding(Some(value)),
        ) if value == "chunked" => (
            "green",
            "HTTP-response-transfer-coding(Some(\"chunked\"))".to_owned(),
        ),
        (
            ProbeCase::HttpResponseContentCoding,
            ErrorCode::HttpResponseContentCoding(Some(value)),
        ) if value == "gzip" => (
            "green",
            "HTTP-response-content-coding(Some(\"gzip\"))".to_owned(),
        ),
        (ProbeCase::InternalErrorNone, ErrorCode::InternalError(None)) => {
            ("green", "InternalError(None)".to_owned())
        }
        (ProbeCase::InternalErrorSome, ErrorCode::InternalError(Some(value))) if value == "x" => {
            ("green", "InternalError(Some(\"x\"))".to_owned())
        }
        (_, error) => ("blocked", format!("{error:?}")),
    }
}

impl HostWake {
    fn task(self) -> impl for<'a> AccessorTask<'a, State> {
        async move |_accessor| {
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
                        accessor.spawn(
                            HostWake {
                                completion: completion_sender,
                            }
                            .task(),
                        ),
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
                let error = make_error(case);
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

    let (status, observation) = match result.0 {
        Err(error) => observe_error(case, error),
        Ok(response) => {
            let _ = store.data_mut().table.delete(response)?;
            store.data_mut().stats.response_dropped += 1;
            ("blocked", format!("unexpected response for {case_name}"))
        }
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
    let (status, observation) = match result.0 {
        Err(error) => observe_error(case, error),
        Ok(response) => {
            let _ = store.data_mut().table.delete(response)?;
            store.data_mut().stats.response_dropped += 1;
            ("blocked", format!("unexpected response for {case_name}"))
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
        "compiler-gate={status} delivery={} case={} observation={}",
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
    let (status, observation) = match result.0 {
        Err(error) => observe_error(case, error),
        Ok(response) => {
            let _ = store.data_mut().table.delete(response)?;
            store.data_mut().stats.response_dropped += 1;
            ("blocked", format!("unexpected response for {case_name}"))
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
        "service-probe-gate={status} delivery={} case={} observation={}",
        delivery.name(),
        case_name,
        observation
    );
    println!("request-consumed={}", stats.request_consumed);
    println!("response-created={}", stats.response_created);
    println!("table-empty={}", store.data().table.is_empty());
    Ok(())
}
