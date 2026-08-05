use anyhow::{Context, Result, bail};
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Destination, FutureReader, Linker, Resource, ResourceTable, ResourceType,
    StreamProducer, StreamReader, StreamResult, VecBuffer,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const HTTP_TYPES_INSTANCE: &str = "wasi:http/types@0.3.0-rc-2025-09-16";
const HTTP_PROBE_INSTANCE: &str = "wasi:http/probe@0.3.0-rc-2025-09-16";

pub struct Fields;
pub struct Response;

#[derive(
    Clone,
    Debug,
    PartialEq,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(record)]
#[allow(dead_code)]
struct DnsErrorPayload {
    #[component(name = "rcode")]
    rcode: Option<String>,
    #[component(name = "info-code")]
    info_code: Option<u16>,
}

#[derive(
    Clone,
    Debug,
    PartialEq,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(record)]
#[allow(dead_code)]
struct TlsAlertReceivedPayload {
    #[component(name = "alert-id")]
    alert_id: Option<u8>,
    #[component(name = "alert-message")]
    alert_message: Option<String>,
}

#[derive(
    Clone,
    Debug,
    PartialEq,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(record)]
#[allow(dead_code)]
struct FieldSizePayload {
    #[component(name = "field-name")]
    field_name: Option<String>,
    #[component(name = "field-size")]
    field_size: Option<u32>,
}

#[derive(
    Clone,
    Debug,
    PartialEq,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(variant)]
#[allow(dead_code)]
enum ErrorCode {
    #[component(name = "DNS-timeout")]
    DnsTimeout,
    #[component(name = "DNS-error")]
    DnsError(DnsErrorPayload),
    #[component(name = "destination-not-found")]
    DestinationNotFound,
    #[component(name = "destination-unavailable")]
    DestinationUnavailable,
    #[component(name = "destination-IP-prohibited")]
    DestinationIpProhibited,
    #[component(name = "destination-IP-unroutable")]
    DestinationIpUnroutable,
    #[component(name = "connection-refused")]
    ConnectionRefused,
    #[component(name = "connection-terminated")]
    ConnectionTerminated,
    #[component(name = "connection-timeout")]
    ConnectionTimeout,
    #[component(name = "connection-read-timeout")]
    ConnectionReadTimeout,
    #[component(name = "connection-write-timeout")]
    ConnectionWriteTimeout,
    #[component(name = "connection-limit-reached")]
    ConnectionLimitReached,
    #[component(name = "TLS-protocol-error")]
    TlsProtocolError,
    #[component(name = "TLS-certificate-error")]
    TlsCertificateError,
    #[component(name = "TLS-alert-received")]
    TlsAlertReceived(TlsAlertReceivedPayload),
    #[component(name = "HTTP-request-denied")]
    HttpRequestDenied,
    #[component(name = "HTTP-request-length-required")]
    HttpRequestLengthRequired,
    #[component(name = "HTTP-request-body-size")]
    HttpRequestBodySize(Option<u64>),
    #[component(name = "HTTP-request-method-invalid")]
    HttpRequestMethodInvalid,
    #[component(name = "HTTP-request-URI-invalid")]
    HttpRequestUriInvalid,
    #[component(name = "HTTP-request-URI-too-long")]
    HttpRequestUriTooLong,
    #[component(name = "HTTP-request-header-section-size")]
    HttpRequestHeaderSectionSize(Option<u32>),
    #[component(name = "HTTP-request-header-size")]
    HttpRequestHeaderSize(Option<FieldSizePayload>),
    #[component(name = "HTTP-request-trailer-section-size")]
    HttpRequestTrailerSectionSize(Option<u32>),
    #[component(name = "HTTP-request-trailer-size")]
    HttpRequestTrailerSize(FieldSizePayload),
    #[component(name = "HTTP-response-incomplete")]
    HttpResponseIncomplete,
    #[component(name = "HTTP-response-header-section-size")]
    HttpResponseHeaderSectionSize(Option<u32>),
    #[component(name = "HTTP-response-header-size")]
    HttpResponseHeaderSize(FieldSizePayload),
    #[component(name = "HTTP-response-body-size")]
    HttpResponseBodySize(Option<u64>),
    #[component(name = "HTTP-response-trailer-section-size")]
    HttpResponseTrailerSectionSize(Option<u32>),
    #[component(name = "HTTP-response-trailer-size")]
    HttpResponseTrailerSize(FieldSizePayload),
    #[component(name = "HTTP-response-transfer-coding")]
    HttpResponseTransferCoding(Option<String>),
    #[component(name = "HTTP-response-content-coding")]
    HttpResponseContentCoding(Option<String>),
    #[component(name = "HTTP-response-timeout")]
    HttpResponseTimeout,
    #[component(name = "HTTP-upgrade-failed")]
    HttpUpgradeFailed,
    #[component(name = "HTTP-protocol-error")]
    HttpProtocolError,
    #[component(name = "loop-detected")]
    LoopDetected,
    #[component(name = "configuration-error")]
    ConfigurationError,
    #[component(name = "internal-error")]
    InternalError(Option<String>),
}

#[derive(Default)]
struct Stats {
    response_consumed: u32,
    response_dropped: u32,
    body_bytes: u32,
    stream_drops: u32,
    future_drops: u32,
}

struct State {
    table: ResourceTable,
    stats: Stats,
}

struct BodyStream {
    stats: Arc<Mutex<Stats>>,
    items: Vec<u8>,
    cursor: usize,
}

impl Drop for BodyStream {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("response body stream stats mutex poisoned")
            .stream_drops += 1;
    }
}

impl StreamProducer<State> for BodyStream {
    type Item = u8;
    type Buffer = VecBuffer<u8>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _: &mut TaskContext<'_>,
        mut store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        _: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        let stream = self.get_mut();
        let Some(&item) = stream.items.get(stream.cursor) else {
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        stream.cursor += 1;
        destination.set_buffer(vec![item].into());
        store.data_mut().stats.body_bytes += 1;
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

struct BodyTrailers {
    stats: Arc<Mutex<Stats>>,
    ready: bool,
    pending_once: bool,
}

impl Drop for BodyTrailers {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("response trailers stats mutex poisoned")
            .future_drops += 1;
    }
}

impl Future for BodyTrailers {
    type Output = wasmtime::Result<std::result::Result<Option<Resource<Fields>>, ErrorCode>>;

    fn poll(self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        let trailers = self.get_mut();
        if trailers.ready || !trailers.pending_once {
            Poll::Ready(Ok(Ok(None)))
        } else {
            trailers.pending_once = false;
            cx.waker().wake_by_ref();
            Poll::Pending
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn install_types(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    body_item_count: usize,
    trailers_ready: bool,
) -> wasmtime::Result<()> {
    let mut types = linker.instance(HTTP_TYPES_INSTANCE)?;
    types.resource(
        "fields",
        ResourceType::host::<Fields>(),
        |mut store, rep| {
            store
                .data_mut()
                .table
                .delete(Resource::<Fields>::new_own(rep))?;
            Ok(())
        },
    )?;
    types.resource(
        "response",
        ResourceType::host::<Response>(),
        |mut store, rep| {
            let state = store.data_mut();
            state.table.delete(Resource::<Response>::new_own(rep))?;
            state.stats.response_dropped += 1;
            Ok(())
        },
    )?;

    types.func_wrap(
        "[static]response.consume-body",
        move |mut store,
              (response, input): (
            Resource<Response>,
            FutureReader<std::result::Result<(), ErrorCode>>,
        )| {
            let mut input = input;
            // This host does not consume the cancellation payload; close the reader
            // so the guest-owned writer can finish without leaking the future.
            input.close(&mut store)?;
            let state = store.data_mut();
            state.table.delete(response)?;
            state.stats.response_consumed += 1;

            let stream = StreamReader::new(
                &mut store,
                BodyStream {
                    stats: Arc::clone(&stats),
                    items: vec![0x61, 0x62, 0x63]
                        .into_iter()
                        .take(body_item_count)
                        .collect(),
                    cursor: 0,
                },
            )?;
            let trailers = FutureReader::new(
                &mut store,
                BodyTrailers {
                    stats: Arc::clone(&stats),
                    ready: trailers_ready,
                    pending_once: !trailers_ready,
                },
            )?;
            Ok(((stream, trailers),))
        },
    )?;
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-http-response-consume-body-host-runner <component.wasm>")?;
    let expected_body_bytes = std::env::args()
        .nth(2)
        .map(|value| value.parse::<u32>())
        .transpose()
        .context("expected body byte count must be an unsigned integer")?;
    let body_item_count = std::env::args()
        .nth(3)
        .map(|value| value.parse::<usize>())
        .transpose()
        .context("body item count must be an unsigned integer")?
        .unwrap_or(3);
    let trailers_ready = std::env::args()
        .nth(4)
        .map(|value| value.parse::<u32>())
        .transpose()
        .context("trailers ready flag must be an unsigned integer")?
        .is_some_and(|value| value != 0);
    futures::executor::block_on(run(
        Path::new(&component_path),
        expected_body_bytes,
        body_item_count,
        trailers_ready,
    ))
}

async fn run(
    component_path: &Path,
    expected_body_bytes: Option<u32>,
    body_item_count: usize,
    trailers_ready: bool,
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
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_types(
        &mut linker,
        Arc::clone(&stats),
        body_item_count,
        trailers_ready,
    ))?;

    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Stats::default(),
        },
    );
    let response = store.data_mut().table.push(Response)?;
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, HTTP_PROBE_INSTANCE)
        .context("missing wasi:http/probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing wasi:http/probe.run export")?;
    let run = map_wasmtime(instance.get_typed_func::<(Resource<Response>,), ()>(&mut store, &run))?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, (response,)).await)
            .await,
    )?;
    map_wasmtime(call)?;

    let body_stats = stats.lock().expect("response body stats mutex poisoned");
    let store_stats = &store.data().stats;
    if store_stats.response_consumed != 1
        || store_stats.response_dropped != 0
        || body_stats.stream_drops != 1
        || body_stats.future_drops != 1
        || expected_body_bytes.is_some_and(|expected| store_stats.body_bytes != expected)
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected HTTP response body stats: consumed={} dropped={} body-bytes={} stream-drops={} future-drops={} table-empty={}",
            store_stats.response_consumed,
            store_stats.response_dropped,
            store_stats.body_bytes,
            body_stats.stream_drops,
            body_stats.future_drops,
            store.data().table.is_empty(),
        );
    }

    println!("Rust P3 HTTP response consume-body adapter passed");
    println!("response-consumed={}", store_stats.response_consumed);
    println!("body-bytes={}", store_stats.body_bytes);
    println!("stream-drops={}", body_stats.stream_drops);
    println!("future-drops={}", body_stats.future_drops);
    println!("table-empty={}", store.data().table.is_empty());
    Ok(())
}
