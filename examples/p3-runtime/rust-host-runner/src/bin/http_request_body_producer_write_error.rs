use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Func, FutureReader, Linker, Resource, ResourceTable, ResourceType, StreamConsumer,
    StreamReader, StreamResult, Val,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const HTTP_TYPES_INSTANCE: &str = "wasi:http/types@0.3.0-rc-2025-09-16";
const HTTP_CLIENT_INSTANCE: &str = "wasi:http/client@0.3.0-rc-2025-09-16";
const HTTP_PROBE_INSTANCE: &str = "wasi:http/probe@0.3.0-rc-2025-09-16";
const CLI_STDOUT_INSTANCE: &str = "wasi:cli/stdout@0.3.0-rc-2025-09-16";

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
    fields_drops: u32,
    transmission_future_drops: u32,
    trailers_future_drops: u32,
    body_stream_drops: u32,
    body_payloads: Vec<Vec<u8>>,
    send_cancellations: u32,
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

struct DiscardConsumer;

impl StreamConsumer<State> for DiscardConsumer {
    type Item = u8;

    fn poll_consume(
        self: Pin<&mut Self>,
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
        Poll::Ready(Ok(StreamResult::Dropped))
    }
}

struct CloseAfterFirstConsumer {
    stats: Arc<Mutex<Stats>>,
    body: Vec<u8>,
    dropped: Option<oneshot::Sender<()>>,
    finish_seen: bool,
}

impl StreamConsumer<State> for CloseAfterFirstConsumer {
    type Item = u8;

    fn poll_consume(
        mut self: Pin<&mut Self>,
        _cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'_, State>,
        mut source: wasmtime::component::Source<'_, Self::Item>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            self.finish_seen = true;
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

impl Drop for CloseAfterFirstConsumer {
    fn drop(&mut self) {
        let mut stats = self.stats.lock().expect("body stream stats mutex poisoned");
        stats.body_stream_drops += 1;
        stats.body_payloads.push(std::mem::take(&mut self.body));
        drop(stats);
        if let Some(sender) = self.dropped.take() {
            let _ = sender.send(());
        }
    }
}

struct SendCancellationGuard(Arc<Mutex<Stats>>);

impl Drop for SendCancellationGuard {
    fn drop(&mut self) {
        self.0
            .lock()
            .expect("send stats mutex poisoned")
            .send_cancellations += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args().nth(1).context(
        "usage: do-p3-http-request-body-producer-write-error-host-runner <component.wasm>",
    )?;
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
    let component = map_wasmtime(Component::from_file(&engine, component_path))?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker: Linker<State> = Linker::new(&engine);

    let mut stdout = map_wasmtime(linker.instance(CLI_STDOUT_INSTANCE))?;
    map_wasmtime(stdout.func_wrap_concurrent(
        "write-via-stream",
        move |accessor, (reader,): (StreamReader<u8>,)| {
            Box::pin(async move {
                accessor.with(|mut store| reader.pipe(&mut store, DiscardConsumer))?;
                Ok::<(std::result::Result<(), wasi::cli::types::ErrorCode>,), wasmtime::Error>((
                    Ok(()),
                ))
            })
        },
    ))?;

    let mut types = map_wasmtime(linker.instance(HTTP_TYPES_INSTANCE))?;
    map_wasmtime(types.resource(
        "fields",
        ResourceType::host::<Fields>(),
        |mut store, rep| {
            store
                .data_mut()
                .table
                .delete(Resource::<Fields>::new_own(rep))?;
            store
                .data_mut()
                .stats
                .lock()
                .expect("stats mutex poisoned")
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
            store
                .data_mut()
                .table
                .delete(Resource::<Response>::new_own(rep))?;
            store
                .data_mut()
                .stats
                .lock()
                .expect("stats mutex poisoned")
                .responses += 1;
            Ok(())
        },
    ))?;
    map_wasmtime(types.func_wrap("[constructor]fields", |mut store, ()| {
        Ok((store.data_mut().table.push(Fields)?,))
    }))?;

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
            let body = contents.ok_or_else(|| wasmtime::Error::msg("request body is missing"))?;
            if options.is_some() {
                return Err(wasmtime::Error::msg("request options unexpectedly present"));
            }
            trailers.close(&mut store)?;
            {
                let state = store.data_mut();
                state.table.delete(headers)?;
                let mut stats = state.stats.lock().expect("request stats mutex poisoned");
                stats.requests += 1;
                stats.fields_drops += 1;
                stats.trailers_future_drops += 1;
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

    let send_stats = Arc::clone(&stats);
    let mut client = map_wasmtime(linker.instance(HTTP_CLIENT_INSTANCE))?;
    map_wasmtime(client.func_wrap_concurrent(
        "send",
        move |accessor, (request,): (Resource<Request>,)| {
            let mut request = match accessor
                .with(|mut store| store.data_mut().table.delete(request))
            {
                Ok(request) => request,
                Err(error) => {
                    return Box::pin(async move { Err(wasmtime::Error::msg(error.to_string())) });
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
            if let Err(error) = accessor.with(|mut store| {
                body.pipe(
                    &mut store,
                    CloseAfterFirstConsumer {
                        stats: Arc::clone(&send_stats),
                        body: Vec::new(),
                        dropped: Some(dropped_sender),
                        finish_seen: false,
                    },
                )
            }) {
                return Box::pin(async move { Err(error) });
            }
            let stats = Arc::clone(&send_stats);
            Box::pin(async move {
                let _cancelled = SendCancellationGuard(stats);
                dropped_receiver
                    .await
                    .map_err(|_| wasmtime::Error::msg("body consumer dropped before first byte"))?;
                std::future::pending::<
                    wasmtime::Result<(
                        std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>,
                    )>,
                >()
                .await
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
    let run: Func = instance
        .get_func(&mut store, &run)
        .context("probe.run is not a function")?;
    let mut results = [Val::Result(Err(Some(Box::new(Val::Variant(
        "http-failure".to_string(),
        None,
    )))))];
    map_wasmtime(run.call_async(&mut store, &[], &mut results).await)?;
    match &results[0] {
        Val::Result(Err(Some(error))) if matches!(error.as_ref(), Val::Variant(name, None) if name == "stream-closed") =>
            {}
        other => bail!("expected Err(stream-closed), got {other:?}"),
    }

    let snapshot = stats.lock().expect("producer stats mutex poisoned");
    if snapshot.requests != 1
        || snapshot.responses != 0
        || snapshot.fields_drops != 1
        || snapshot.transmission_future_drops != 1
        || snapshot.trailers_future_drops != 1
        || snapshot.body_stream_drops != 1
        || snapshot.body_payloads != vec![vec![65]]
        || snapshot.send_cancellations != 1
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected producer failure stats: requests={} responses={} fields-drops={} transmission-future-drops={} trailers-future-drops={} body-stream-drops={} body-payloads={:?} send-cancellations={} table-empty={}",
            snapshot.requests,
            snapshot.responses,
            snapshot.fields_drops,
            snapshot.transmission_future_drops,
            snapshot.trailers_future_drops,
            snapshot.body_stream_drops,
            snapshot.body_payloads,
            snapshot.send_cancellations,
            store.data().table.is_empty(),
        );
    }

    println!("result=Err(StreamClosed)");
    println!("body-payload={:?}", snapshot.body_payloads[0]);
    println!("send-cancellations={}", snapshot.send_cancellations);
    println!("body-stream-drops={}", snapshot.body_stream_drops);
    println!(
        "transmission-future-drops={}",
        snapshot.transmission_future_drops
    );
    println!("trailers-future-drops={}", snapshot.trailers_future_drops);
    println!("responses={}", snapshot.responses);
    println!("table-empty={}", store.data().table.is_empty());
    println!("Rust P3 HTTP request body producer write-error passed");
    Ok(())
}
