use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::future::Future;
use std::mem;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Destination, FutureReader, Linker, Resource, ResourceTable, ResourceType,
    StreamConsumer, StreamProducer, StreamReader, StreamResult, VecBuffer,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const HTTP_TYPES_INSTANCE: &str = "wasi:http/types@0.3.0-rc-2025-09-16";
const HTTP_CLIENT_INSTANCE: &str = "wasi:http/client@0.3.0-rc-2025-09-16";
const HTTP_PROBE_INSTANCE: &str = "wasi:http/probe@0.3.0-rc-2025-09-16";
const CLI_TYPES_INSTANCE: &str = "wasi:cli/types@0.3.0-rc-2025-09-16";
const CLI_STDIN_INSTANCE: &str = "wasi:cli/stdin@0.3.0-rc-2025-09-16";

pub struct Fields;
pub struct Request {
    body: Option<StreamReader<u8>>,
}
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
    responses: u32,
    response_drops: u32,
    fields_drops: u32,
    transmission_future_drops: u32,
    trailers_future_drops: u32,
    body_future_drops: u32,
    body_completion_polls: u32,
    body_completion_ready: u32,
    body_completion_ready_before_request: u32,
    body_stream_drops: u32,
    body_payloads: Vec<Vec<u8>>,
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

struct RecordingBodySource {
    items: Vec<u8>,
    stats: Arc<Mutex<Stats>>,
}

impl StreamProducer<State> for RecordingBodySource {
    type Item = u8;
    type Buffer = VecBuffer<u8>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        _store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let source = self.get_mut();
        let items = mem::take(&mut source.items);
        destination.set_buffer(items.into());
        Poll::Ready(Ok(StreamResult::Dropped))
    }
}

impl Drop for RecordingBodySource {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("body stream stats mutex poisoned")
            .body_stream_drops += 1;
    }
}

struct RecordingBodyConsumer {
    stats: Arc<Mutex<Stats>>,
    body: Vec<u8>,
    dropped: Option<oneshot::Sender<()>>,
}

impl StreamConsumer<State> for RecordingBodyConsumer {
    type Item = u8;

    fn poll_consume(
        mut self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'_, State>,
        mut source: wasmtime::component::Source<'_, Self::Item>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let remaining = source.remaining(&mut store);
        if remaining == 0 {
            return Poll::Pending;
        }
        let mut items = Vec::with_capacity(remaining);
        source.read(&mut store, &mut items)?;
        self.body.extend_from_slice(&items);
        Poll::Ready(Ok(StreamResult::Dropped))
    }
}

impl Drop for RecordingBodyConsumer {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("body consumer stats mutex poisoned")
            .body_payloads
            .push(mem::take(&mut self.body));
        if let Some(sender) = self.dropped.take() {
            let _ = sender.send(());
        }
    }
}

struct SourceCompletion {
    stats: Arc<Mutex<Stats>>,
    pending_once: bool,
    polled: bool,
}

impl Future for SourceCompletion {
    type Output = wasmtime::Result<std::result::Result<(), wasi::cli::types::ErrorCode>>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        let pending = self.pending_once && !self.polled;
        if pending {
            self.polled = true;
        }
        let mut stats = self.stats.lock().expect("body future stats mutex poisoned");
        stats.body_completion_polls += 1;
        if pending {
            drop(stats);
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        stats.body_completion_ready += 1;
        Poll::Ready(Ok(Ok(())))
    }
}

impl Drop for SourceCompletion {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("body future stats mutex poisoned")
            .body_future_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-http-request-body-host-runner <component.wasm>")?;
    let completion_pending_once = std::env::var_os("DO_HTTP_BODY_COMPLETION_READY").is_none();
    let expected_body_completion_polls = std::env::var("DO_HTTP_BODY_COMPLETION_EXPECTED_POLLS")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(0);
    let require_completion_ready_before_request =
        std::env::var_os("DO_HTTP_BODY_COMPLETION_REQUIRE_READY").is_some();
    futures::executor::block_on(run(
        Path::new(&component_path),
        completion_pending_once,
        expected_body_completion_polls,
        require_completion_ready_before_request,
    ))
}

async fn run(
    component_path: &Path,
    completion_pending_once: bool,
    expected_body_completion_polls: u32,
    require_completion_ready_before_request: bool,
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
    let mut linker: Linker<State> = Linker::new(&engine);
    let _ = map_wasmtime(linker.instance(CLI_TYPES_INSTANCE))?;

    let stdin_stats = Arc::clone(&stats);
    let mut stdin = map_wasmtime(linker.instance(CLI_STDIN_INSTANCE))?;
    map_wasmtime(stdin.func_wrap("read-via-stream", move |mut store, ()| {
        let reader = StreamReader::new(
            &mut store,
            RecordingBodySource {
                items: vec![65, 66],
                stats: Arc::clone(&stdin_stats),
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            SourceCompletion {
                stats: Arc::clone(&stdin_stats),
                pending_once: completion_pending_once,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    }))?;

    let mut types = map_wasmtime(linker.instance(HTTP_TYPES_INSTANCE))?;
    map_wasmtime(types.resource(
        "fields",
        ResourceType::host::<Fields>(),
        |mut store, rep| {
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
        |mut store, rep| {
            let mut request = store
                .data_mut()
                .table
                .delete(Resource::<Request>::new_own(rep))?;
            if let Some(mut body) = request.body.take() {
                body.close(&mut store)?;
            }
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
            state
                .stats
                .lock()
                .expect("response stats mutex poisoned")
                .response_drops += 1;
            Ok(())
        },
    ))?;

    map_wasmtime(
        types.func_wrap("[constructor]fields", move |mut store, ()| {
            let fields = store.data_mut().table.push(Fields)?;
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
            let ready_before_request = {
                let state = store.data_mut();
                let mut stats = state
                    .stats
                    .lock()
                    .expect("request ordering stats mutex poisoned");
                let expected_ready = stats.requests + 1;
                let ready = stats.body_completion_ready >= expected_ready;
                if ready {
                    stats.body_completion_ready_before_request += 1;
                }
                ready
            };
            if require_completion_ready_before_request && !ready_before_request {
                return Err(wasmtime::Error::msg(
                    "request.new ran before source completion became ready",
                ));
            }
            let body = contents.ok_or_else(|| wasmtime::Error::msg("request body is missing"))?;
            if options.is_some() {
                return Err(wasmtime::Error::msg("request options unexpectedly present"));
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
            let request = store.data_mut().table.push(Request { body: Some(body) })?;
            let transmission = FutureReader::new(
                &mut store,
                TransmissionCompletion {
                    stats: Arc::clone(&transmission_stats),
                },
            )?;
            Ok(((request, transmission),))
        },
    ))?;

    let mut client = map_wasmtime(linker.instance(HTTP_CLIENT_INSTANCE))?;
    let send_stats = Arc::clone(&stats);
    map_wasmtime(client.func_wrap_concurrent(
        "send",
        move |accessor, (request,): (Resource<Request>,)| {
            let mut request =
                match accessor.with(|mut store| store.data_mut().table.delete(request)) {
                    Ok(request) => request,
                    Err(error) => {
                        let error = wasmtime::Error::msg(error.to_string());
                        return Box::pin(async move { Err(error) });
                    }
                };
            let body = match request.body.take() {
                Some(body) => body,
                None => {
                    return Box::pin(async {
                        Err(wasmtime::Error::msg("request body already moved"))
                    });
                }
            };
            let (dropped_sender, dropped_receiver) = oneshot::channel();
            let consumer = RecordingBodyConsumer {
                stats: Arc::clone(&send_stats),
                body: Vec::new(),
                dropped: Some(dropped_sender),
            };
            if let Err(error) = accessor.with(|mut store| body.pipe(&mut store, consumer)) {
                return Box::pin(async move { Err(error) });
            }
            let call_number = {
                let stats = send_stats.lock().expect("send stats mutex poisoned");
                stats.requests + 1
            };
            send_stats
                .lock()
                .expect("send stats mutex poisoned")
                .requests = call_number;
            Box::pin(async move {
                dropped_receiver
                    .await
                    .map_err(|_| wasmtime::Error::msg("body consumer dropped before completion"))?;
                if call_number == 2 {
                    return Ok::<
                        (std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>,),
                        wasmtime::Error,
                    >((Err(wasi::http::types::ErrorCode::DnsTimeout),));
                }
                let response = accessor.with(|mut store| {
                    let response = store.data_mut().table.push(Response)?;
                    store
                        .data_mut()
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

    let first = map_wasmtime(map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(accessor, ()).await)
            .await,
    )?)?;
    let first_response = first
        .0
        .map_err(|error| anyhow::anyhow!("expected first Ok(response), got {error:?}"))?;
    store.data_mut().table.delete(first_response)?;
    store
        .data_mut()
        .stats
        .lock()
        .expect("response stats mutex poisoned")
        .response_drops += 1;

    let second = map_wasmtime(map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(accessor, ()).await)
            .await,
    )?)?;
    match second.0 {
        Err(wasi::http::types::ErrorCode::DnsTimeout) => {}
        other => bail!("expected second Err(DnsTimeout), got {other:?}"),
    }

    let snapshot = stats.lock().expect("body stats mutex poisoned");
    if snapshot.requests != 2
        || snapshot.responses != 1
        || snapshot.response_drops != 1
        || snapshot.fields_drops != 2
        || snapshot.transmission_future_drops != 2
        || snapshot.trailers_future_drops != 2
        || snapshot.body_future_drops != 2
        || snapshot.body_completion_polls != expected_body_completion_polls
        || (require_completion_ready_before_request
            && snapshot.body_completion_ready_before_request != 2)
        || snapshot.body_stream_drops != 2
        || snapshot.body_payloads != vec![vec![65, 66], vec![65, 66]]
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected HTTP body stats: requests={} responses={} response-drops={} fields-drops={} transmission-future-drops={} trailers-future-drops={} body-future-drops={} body-completion-polls={} expected-body-completion-polls={} body-completion-ready={} body-completion-ready-before-request={} body-stream-drops={} body-payloads={:?} table-empty={}",
            snapshot.requests,
            snapshot.responses,
            snapshot.response_drops,
            snapshot.fields_drops,
            snapshot.transmission_future_drops,
            snapshot.trailers_future_drops,
            snapshot.body_future_drops,
            snapshot.body_completion_polls,
            expected_body_completion_polls,
            snapshot.body_completion_ready,
            snapshot.body_completion_ready_before_request,
            snapshot.body_stream_drops,
            snapshot.body_payloads,
            store.data().table.is_empty(),
        );
    }

    println!("Rust P3 HTTP request body adapter passed");
    println!("body-payloads={:?}", snapshot.body_payloads);
    println!("body-future-drops={}", snapshot.body_future_drops);
    println!(
        "body-completion-mode={}",
        if completion_pending_once {
            "pending-once"
        } else {
            "ready"
        }
    );
    println!("body-completion-polls={}", snapshot.body_completion_polls);
    println!(
        "expected-body-completion-polls={}",
        expected_body_completion_polls
    );
    println!(
        "body-completion-ready-before-request={}",
        snapshot.body_completion_ready_before_request == 2
    );
    println!("body-stream-drops={}", snapshot.body_stream_drops);
    println!("responses={}", snapshot.responses);
    println!("table-empty={}", store.data().table.is_empty());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use futures::task::noop_waker;

    #[test]
    fn source_completion_supports_ready_and_one_poll_pending_modes() {
        let stats = Arc::new(Mutex::new(Stats::default()));
        let waker = noop_waker();
        let mut context = TaskContext::from_waker(&waker);

        let mut pending_once = SourceCompletion {
            stats: Arc::clone(&stats),
            pending_once: true,
            polled: false,
        };
        assert!(matches!(
            Pin::new(&mut pending_once).poll(&mut context),
            Poll::Pending
        ));
        assert!(matches!(
            Pin::new(&mut pending_once).poll(&mut context),
            Poll::Ready(Ok(Ok(())))
        ));

        let mut ready = SourceCompletion {
            stats: Arc::clone(&stats),
            pending_once: false,
            polled: false,
        };
        assert!(matches!(
            Pin::new(&mut ready).poll(&mut context),
            Poll::Ready(Ok(Ok(())))
        ));
        assert_eq!(
            stats
                .lock()
                .expect("body future stats mutex poisoned")
                .body_completion_polls,
            3
        );
    }
}
