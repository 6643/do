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

const HTTP_INSTANCE: &str = "do:resource-probe-owned-error/http@0.1.0";

pub struct Request;
pub struct Response;
pub struct ErrorResource;

wasmtime::component::bindgen!({
    inline: r#"
        package probe:owned-error-types@0.1.0;

        interface http {
          resource request {}
          resource response {}
          resource error-resource {}

          send: async func(request: request) -> result<response, error-resource>;
        }

        world owned-error-result-types {
          import http;
        }
    "#,
    world: "owned-error-result-types",
    imports: { default: async | trappable },
    exports: { default: async },
    with: {
        "probe:owned-error-types/http.request": Request,
        "probe:owned-error-types/http.response": Response,
        "probe:owned-error-types/http.error-resource": ErrorResource,
    },
});

#[derive(Default)]
struct Stats {
    request_consumed: u32,
    response_created: u32,
    response_dropped: u32,
    error_created: u32,
    error_dropped: u32,
}

#[derive(Default)]
struct TaskStats {
    pending_polls: u32,
    external_wakes: u32,
    completions: u32,
}

struct State {
    table: ResourceTable,
    stats: Stats,
}

struct PendingSend {
    stats: Arc<Mutex<TaskStats>>,
    completion: oneshot::Receiver<()>,
    pending_recorded: bool,
}

impl Future for PendingSend {
    type Output = wasmtime::Result<()>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        match Pin::new(&mut self.completion).poll(cx) {
            Poll::Pending => {
                if !self.pending_recorded {
                    self.pending_recorded = true;
                    self.stats
                        .lock()
                        .expect("owned-error task stats mutex poisoned")
                        .pending_polls += 1;
                }
                Poll::Pending
            }
            Poll::Ready(Ok(())) => {
                self.stats
                    .lock()
                    .expect("owned-error task stats mutex poisoned")
                    .completions += 1;
                Poll::Ready(Ok(()))
            }
            Poll::Ready(Err(_)) => {
                Poll::Ready(Err(wasmtime::Error::msg("owned-error host wake dropped")))
            }
        }
    }
}

struct HostWake {
    stats: Arc<Mutex<TaskStats>>,
    completion: oneshot::Sender<()>,
}

impl AccessorTask<State> for HostWake {
    fn run(self, _accessor: &Accessor<State>) -> impl Future<Output = wasmtime::Result<()>> + Send {
        async move {
            self.stats
                .lock()
                .expect("owned-error task stats mutex poisoned")
                .external_wakes += 1;
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
        .context("usage: do-p3-owned-error-result-shape-host-runner <component.wasm>")?;
    futures::executor::block_on(run(Path::new(&component_path)))
}

async fn run(component_path: &Path) -> Result<()> {
    let immediate = std::env::var_os("DO_P3_OWNED_ERROR_IMMEDIATE").is_some();
    let error_mode = std::env::var_os("DO_P3_OWNED_ERROR_ERR").is_some();
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.wasm_gc(true);
    config.concurrency_support(true);

    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let task_stats = Arc::new(Mutex::new(TaskStats::default()));
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

    let send_task_stats = Arc::clone(&task_stats);
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
                    let error = accessor.with(|mut access| {
                        let state = access.data_mut();
                        let error = state.table.push(ErrorResource)?;
                        state.stats.error_created += 1;
                        Ok::<Resource<ErrorResource>, wasmtime::Error>(error)
                    })?;
                    Ok::<
                        (std::result::Result<Resource<Response>, Resource<ErrorResource>>,),
                        wasmtime::Error,
                    >((Err(error),))
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
                        (std::result::Result<Resource<Response>, Resource<ErrorResource>>,),
                        wasmtime::Error,
                    >((Ok(response),))
                });
            }
            let (sender, completion) = oneshot::channel();
            let host_event = accessor.spawn(HostWake {
                stats: Arc::clone(&send_task_stats),
                completion: sender,
            });
            let pending = PendingSend {
                stats: Arc::clone(&send_task_stats),
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
                    (std::result::Result<Resource<Response>, Resource<ErrorResource>>,),
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
        std::result::Result<Resource<Response>, Resource<ErrorResource>>,
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

    for (result,) in [results.0, results.1] {
        if error_mode {
            let error = match result {
                Ok(_) => bail!("expected Err(error-resource), got Ok(response)"),
                Err(error) => error,
            };
            let _ = store.data_mut().table.delete(error)?;
            store.data_mut().stats.error_dropped += 1;
        } else {
            let response = match result {
                Ok(response) => response,
                Err(_) => bail!("expected Ok(response), got Err(error-resource)"),
            };
            let _ = store.data_mut().table.delete(response)?;
            store.data_mut().stats.response_dropped += 1;
        }
    }

    let stats = &store.data().stats;
    if stats.request_consumed != 2
        || stats.response_created != if error_mode { 0 } else { 2 }
        || stats.response_dropped != if error_mode { 0 } else { 2 }
        || stats.error_created != if error_mode { 2 } else { 0 }
        || stats.error_dropped != if error_mode { 2 } else { 0 }
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected owned-error stats: request-consumed={} response-created={} response-dropped={} error-created={} error-dropped={} table-empty={}",
            stats.request_consumed,
            stats.response_created,
            stats.response_dropped,
            stats.error_created,
            stats.error_dropped,
            store.data().table.is_empty(),
        );
    }
    let task_stats = task_stats
        .lock()
        .expect("owned-error task stats mutex poisoned");
    let expected_tasks = if immediate || error_mode {
        (0, 0, 0)
    } else {
        (2, 2, 2)
    };
    if (
        task_stats.pending_polls,
        task_stats.external_wakes,
        task_stats.completions,
    ) != expected_tasks
    {
        bail!(
            "expected owned-error task stats {:?}, got ({}, {}, {})",
            expected_tasks,
            task_stats.pending_polls,
            task_stats.external_wakes,
            task_stats.completions,
        );
    }
    let mode = if error_mode {
        "error"
    } else if immediate {
        "immediate"
    } else {
        "pending"
    };
    println!("Rust P3 owned-error Result {mode} adapter passed");
    println!("request consumed=2");
    println!("response create={}", stats.response_created);
    println!("response drop={}", stats.response_dropped);
    println!("error-resource create={}", stats.error_created);
    println!("error-resource drop={}", stats.error_dropped);
    println!("table-empty=true");
    Ok(())
}
