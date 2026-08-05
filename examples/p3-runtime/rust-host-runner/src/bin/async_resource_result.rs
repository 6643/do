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

const HTTP_INSTANCE: &str = "do:resource-probe/http@0.1.0";

pub struct Request;
pub struct Response;

wasmtime::component::bindgen!({
    inline: r#"
        package probe:resource-types@0.1.0;

        interface http {
          resource request {}
          resource response {}

          enum error-code {
            failed,
          }

          send: async func(request: request) -> result<response, error-code>;
        }

        world async-resource-types {
          import http;
        }
    "#,
    world: "async-resource-types",
    imports: { default: async | trappable },
    exports: { default: async },
    with: {
        "probe:resource-types/http.request": Request,
        "probe:resource-types/http.response": Response,
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

struct PendingResponse {
    stats: Arc<Mutex<(u32, u32, u32)>>,
    completion: oneshot::Receiver<()>,
    pending_recorded: bool,
}

impl Future for PendingResponse {
    type Output = wasmtime::Result<()>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        match Pin::new(&mut self.completion).poll(cx) {
            Poll::Pending => {
                if !self.pending_recorded {
                    self.pending_recorded = true;
                    self.stats
                        .lock()
                        .expect("async resource stats mutex poisoned")
                        .0 += 1;
                }
                Poll::Pending
            }
            Poll::Ready(Ok(())) => {
                self.stats
                    .lock()
                    .expect("async resource stats mutex poisoned")
                    .2 += 1;
                Poll::Ready(Ok(()))
            }
            Poll::Ready(Err(_)) => Poll::Ready(Err(wasmtime::Error::msg(
                "async resource host event dropped",
            ))),
        }
    }
}

struct HostWake {
    stats: Arc<Mutex<(u32, u32, u32)>>,
    completion: oneshot::Sender<()>,
}

impl AccessorTask<State> for HostWake {
    fn run(self, _accessor: &Accessor<State>) -> impl Future<Output = wasmtime::Result<()>> + Send {
        async move {
            self.stats
                .lock()
                .expect("async resource stats mutex poisoned")
                .1 += 1;
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
        .context("usage: do-p3-async-resource-result-host-runner <component.wasm>")?;
    futures::executor::block_on(run(Path::new(&component_path)))
}

async fn run(component_path: &Path) -> Result<()> {
    let immediate = std::env::var_os("DO_P3_ASYNC_RESOURCE_IMMEDIATE").is_some();
    let error_mode = std::env::var_os("DO_P3_ASYNC_RESOURCE_ERROR").is_some();
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.wasm_gc(true);
    config.concurrency_support(true);

    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let task_stats = Arc::new(Mutex::new((0, 0, 0)));
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

    let host_task_stats = Arc::clone(&task_stats);
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
            if error_mode {
                return Box::pin(async move {
                    Ok::<
                        (
                            std::result::Result<
                                Resource<Response>,
                                probe::resource_types::http::ErrorCode,
                            >,
                        ),
                        wasmtime::Error,
                    >((Err(probe::resource_types::http::ErrorCode::Failed),))
                });
            }
            if immediate {
                return Box::pin(async move {
                    let response = accessor.with(|mut access| {
                        let state = access.data_mut();
                        let response = state.table.push(Response)?;
                        state.stats.response_created += 1;
                        Ok::<Resource<Response>, wasmtime::Error>(response)
                    })?;
                    Ok::<
                        (
                            std::result::Result<
                                Resource<Response>,
                                probe::resource_types::http::ErrorCode,
                            >,
                        ),
                        wasmtime::Error,
                    >((Ok(response),))
                });
            }
            let (completion_sender, completion) = oneshot::channel();
            let host_event = accessor.spawn(HostWake {
                stats: Arc::clone(&host_task_stats),
                completion: completion_sender,
            });
            let pending = PendingResponse {
                stats: Arc::clone(&host_task_stats),
                completion,
                pending_recorded: false,
            };
            Box::pin(async move {
                host_event?;
                pending.await?;
                let response = accessor.with(|mut access| {
                    let state = access.data_mut();
                    let response = state.table.push(Response)?;
                    state.stats.response_created += 1;
                    Ok::<Resource<Response>, wasmtime::Error>(response)
                })?;
                Ok::<
                    (
                        std::result::Result<
                            Resource<Response>,
                            probe::resource_types::http::ErrorCode,
                        >,
                    ),
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
    let run = map_wasmtime(instance.get_typed_func::<(Resource<Request>,), (
        std::result::Result<Resource<Response>, probe::resource_types::http::ErrorCode>,
    )>(&mut store, "run"))?;

    let results = map_wasmtime(map_wasmtime(
        store
            .run_concurrent(async |accessor| {
                futures::try_join!(
                    run.call_concurrent(accessor, (first_request,)),
                    run.call_concurrent(accessor, (second_request,)),
                )
            })
            .await,
    )?)?;
    if error_mode {
        for (result,) in [results.0, results.1] {
            if result.is_ok() {
                bail!("expected Err(failed), got Ok(response)");
            }
        }
        let stats = &store.data().stats;
        if stats.request_consumed != 2
            || stats.response_created != 0
            || stats.response_dropped != 0
            || !store.data().table.is_empty()
        {
            bail!(
                "unexpected error stats: request-consumed={} response-created={} response-dropped={} table-empty={}",
                stats.request_consumed,
                stats.response_created,
                stats.response_dropped,
                store.data().table.is_empty(),
            );
        }
        println!("Rust P3 async resource Result error adapter passed");
        println!("request consumed=2");
        println!("response create=0");
        println!("response drop=0");
        return Ok(());
    }

    for (result,) in [results.0, results.1] {
        let response =
            result.map_err(|error| anyhow::anyhow!("expected Ok(response), got {error:?}"))?;
        if !response.owned() {
            bail!("expected returned response to be owned by the caller");
        }
        let _ = store.data_mut().table.delete(response)?;
        store.data_mut().stats.response_dropped += 1;
    }

    let task_stats = task_stats
        .lock()
        .expect("async resource stats mutex poisoned");
    let stats = &store.data().stats;
    if stats.request_consumed != 2
        || stats.response_created != 2
        || stats.response_dropped != 2
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected resource stats: request-consumed={} response-created={} response-dropped={}",
            stats.request_consumed,
            stats.response_created,
            stats.response_dropped
        );
    }
    let expected_task_stats = if immediate { (0, 0, 0) } else { (2, 2, 2) };
    if *task_stats != expected_task_stats {
        bail!("expected task stats {expected_task_stats:?}, got {task_stats:?}");
    }

    println!(
        "Rust P3 async resource Result {} adapter passed",
        if immediate { "immediate" } else { "pending" }
    );
    println!("request consumed=2");
    println!("response create=2");
    println!("response drop=2");
    Ok(())
}
