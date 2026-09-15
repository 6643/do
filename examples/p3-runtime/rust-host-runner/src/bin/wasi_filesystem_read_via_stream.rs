use anyhow::{Context, Result, bail};
use std::collections::VecDeque;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Accessor, AccessorTask, Component, Destination, FutureReader, Linker, Resource, ResourceTable,
    ResourceType, StreamProducer, StreamReader, StreamResult, TypedFunc, VecBuffer,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const TYPES_INSTANCE: &str = "wasi:filesystem/types@0.3.0-rc-2025-09-16";
const PROBE_INSTANCE: &str = "wasi:filesystem/probe@0.3.0-rc-2025-09-16";

#[derive(Debug)]
struct Descriptor;

#[derive(
    Clone,
    Copy,
    Debug,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(enum)]
#[repr(u8)]
#[allow(dead_code)]
enum ErrorCode {
    #[component(name = "io")]
    Io,
    #[component(name = "no-entry")]
    NoEntry,
}

#[derive(Default, Debug, PartialEq)]
struct Stats {
    method_calls: u32,
    stream_read_calls: u32,
    completion_polls: u32,
    external_wakes: u32,
    completions: u32,
    completion_errors: u32,
    stream_drops: u32,
    future_drops: u32,
    pending_future_drops: u32,
    descriptor_drops: u32,
}

struct State {
    table: ResourceTable,
    stats: Arc<Mutex<Stats>>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Ready,
    Pending,
    Error,
    CancelBeforeEof,
    CancelAfterEof,
    EarlyDrop,
    Repeat,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "ready" => Ok(Self::Ready),
            "pending" => Ok(Self::Pending),
            "error" => Ok(Self::Error),
            "cancel-before-eof" => Ok(Self::CancelBeforeEof),
            "cancel-after-eof" => Ok(Self::CancelAfterEof),
            "early-drop" => Ok(Self::EarlyDrop),
            "repeat" => Ok(Self::Repeat),
            other => bail!(
                "mode must be ready, pending, error, cancel-before-eof, cancel-after-eof, early-drop, or repeat (got {other})"
            ),
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Ready => "ready",
            Self::Pending => "pending",
            Self::Error => "error",
            Self::CancelBeforeEof => "cancel-before-eof",
            Self::CancelAfterEof => "cancel-after-eof",
            Self::EarlyDrop => "early-drop",
            Self::Repeat => "repeat",
        }
    }
}

fn expected_stats(mode: Mode) -> Stats {
    match mode {
        Mode::Ready => Stats {
            method_calls: 1,
            stream_read_calls: 1,
            completion_polls: 1,
            external_wakes: 0,
            completions: 1,
            completion_errors: 0,
            stream_drops: 1,
            future_drops: 1,
            pending_future_drops: 0,
            descriptor_drops: 1,
        },
        Mode::Error => Stats {
            method_calls: 1,
            stream_read_calls: 1,
            completion_polls: 1,
            external_wakes: 0,
            completions: 1,
            completion_errors: 1,
            stream_drops: 1,
            future_drops: 1,
            pending_future_drops: 0,
            descriptor_drops: 1,
        },
        Mode::Pending => Stats {
            method_calls: 1,
            stream_read_calls: 2,
            completion_polls: 2,
            external_wakes: 2,
            completions: 1,
            completion_errors: 0,
            stream_drops: 1,
            future_drops: 1,
            pending_future_drops: 0,
            descriptor_drops: 1,
        },
        Mode::CancelBeforeEof => Stats {
            method_calls: 1,
            stream_read_calls: 1,
            completion_polls: 0,
            external_wakes: 0,
            completions: 0,
            completion_errors: 0,
            stream_drops: 1,
            future_drops: 1,
            pending_future_drops: 1,
            descriptor_drops: 1,
        },
        Mode::CancelAfterEof => Stats {
            method_calls: 1,
            stream_read_calls: 1,
            completion_polls: 2,
            external_wakes: 0,
            completions: 0,
            completion_errors: 0,
            stream_drops: 1,
            future_drops: 1,
            pending_future_drops: 1,
            descriptor_drops: 1,
        },
        Mode::Repeat => Stats {
            method_calls: 2,
            stream_read_calls: 2,
            completion_polls: 2,
            external_wakes: 0,
            completions: 2,
            completion_errors: 0,
            stream_drops: 2,
            future_drops: 2,
            pending_future_drops: 0,
            descriptor_drops: 2,
        },
        Mode::EarlyDrop => Stats {
            method_calls: 1,
            stream_read_calls: 0,
            completion_polls: 0,
            external_wakes: 0,
            completions: 0,
            completion_errors: 0,
            stream_drops: 1,
            future_drops: 1,
            pending_future_drops: 1,
            descriptor_drops: 0,
        },
    }
}

struct ByteStream {
    stats: Arc<Mutex<Stats>>,
    bytes: VecDeque<u8>,
    never_ready: bool,
    pending_once: bool,
    polled: bool,
}

impl StreamProducer<State> for ByteStream {
    type Item = u8;
    type Buffer = VecBuffer<u8>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        _store: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        let stream = self.get_mut();
        let mut stats = stream
            .stats
            .lock()
            .expect("read stream stats mutex poisoned");
        stats.stream_read_calls += 1;
        if stream.never_ready {
            return Poll::Pending;
        }
        if stream.pending_once && !stream.polled {
            stream.polled = true;
            stats.external_wakes += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        let item = stream.bytes.pop_front();
        drop(stats);
        if let Some(byte) = item {
            destination.set_buffer(vec![byte].into());
            Poll::Ready(Ok(StreamResult::Completed))
        } else {
            destination.set_buffer(Vec::new().into());
            Poll::Ready(Ok(StreamResult::Dropped))
        }
    }
}

impl Drop for ByteStream {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("read stream stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct Completion {
    stats: Arc<Mutex<Stats>>,
    never_ready: bool,
    pending_once: bool,
    error: bool,
    polled: bool,
    completed: bool,
}

impl Future for Completion {
    type Output = wasmtime::Result<std::result::Result<(), ErrorCode>>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        let pending = self.pending_once && !self.polled;
        self.polled = true;
        let completes = !self.never_ready && !pending;
        if completes {
            self.completed = true;
        }
        let mut stats = self
            .stats
            .lock()
            .expect("read completion stats mutex poisoned");
        stats.completion_polls += 1;
        if self.never_ready {
            Poll::Pending
        } else if pending {
            stats.external_wakes += 1;
            cx.waker().wake_by_ref();
            Poll::Pending
        } else if self.error {
            stats.completions += 1;
            stats.completion_errors += 1;
            Poll::Ready(Ok(Err(ErrorCode::Io)))
        } else {
            stats.completions += 1;
            Poll::Ready(Ok(Ok(())))
        }
    }
}

fn result_label(mode: Mode) -> &'static str {
    match mode {
        Mode::Ready | Mode::Pending => "Ok",
        Mode::Error => "Err(io)",
        Mode::CancelBeforeEof | Mode::CancelAfterEof => "cancelled",
        Mode::Repeat => "Ok,Ok",
        Mode::EarlyDrop => "store-disposed",
    }
}

impl Drop for Completion {
    fn drop(&mut self) {
        let mut stats = self
            .stats
            .lock()
            .expect("read completion stats mutex poisoned");
        stats.future_drops += 1;
        if !self.completed {
            stats.pending_future_drops += 1;
        }
    }
}

struct RunTask {
    run: TypedFunc<(Resource<Descriptor>, u64), ()>,
    descriptor: Resource<Descriptor>,
    offset: u64,
}

impl AccessorTask<State> for RunTask {
    fn run(self, accessor: &Accessor<State>) -> impl Future<Output = wasmtime::Result<()>> + Send {
        async move {
            self.run
                .call_concurrent(accessor, (self.descriptor, self.offset))
                .await
                .map(|_| ())
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn install_types(
    linker: &mut Linker<State>,
    mode: Mode,
    stats: Arc<Mutex<Stats>>,
) -> wasmtime::Result<()> {
    let mut types = linker.instance(TYPES_INSTANCE)?;
    types.resource(
        "descriptor",
        ResourceType::host::<Descriptor>(),
        |mut store, rep| {
            store
                .data_mut()
                .table
                .delete(Resource::<Descriptor>::new_own(rep))?;
            store
                .data()
                .stats
                .lock()
                .expect("descriptor stats mutex poisoned")
                .descriptor_drops += 1;
            Ok(())
        },
    )?;

    let method_stats = Arc::clone(&stats);
    types.func_wrap_async(
        "[method]descriptor.read-via-stream",
        move |mut store, (_descriptor, _offset): (Resource<Descriptor>, u64)| {
            let method_stats = Arc::clone(&method_stats);
            Box::new(async move {
                method_stats
                    .lock()
                    .expect("read method stats mutex poisoned")
                    .method_calls += 1;
                let stream = StreamReader::new(
                    &mut store,
                    ByteStream {
                        stats: Arc::clone(&method_stats),
                        bytes: if mode == Mode::CancelAfterEof {
                            VecDeque::new()
                        } else {
                            VecDeque::from([0x41])
                        },
                        never_ready: mode == Mode::CancelBeforeEof,
                        pending_once: mode == Mode::Pending,
                        polled: false,
                    },
                )?;
                let completion = FutureReader::new(
                    &mut store,
                    Completion {
                        stats: Arc::clone(&method_stats),
                        never_ready: matches!(mode, Mode::CancelAfterEof | Mode::EarlyDrop),
                        pending_once: mode == Mode::Pending,
                        error: mode == Mode::Error,
                        polled: false,
                        completed: false,
                    },
                )?;
                Ok(((stream, completion),))
            })
        },
    )?;
    Ok(())
}

async fn call_once(
    store: &mut Store<State>,
    run: TypedFunc<(Resource<Descriptor>, u64), ()>,
) -> Result<()> {
    let descriptor = store.data_mut().table.push(Descriptor)?;
    map_wasmtime(run.call_async(store, (descriptor, 0)).await)
}

async fn run(component_path: &Path, mode: Mode) -> Result<()> {
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
    map_wasmtime(install_types(&mut linker, mode, Arc::clone(&stats)))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_INSTANCE)
        .context("missing filesystem read-via-stream probe export")?;
    let run_export = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing filesystem read-via-stream probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(Resource<Descriptor>, u64), ()>(&mut store, &run_export),
    )?;

    if mode == Mode::EarlyDrop {
        let descriptor = store.data_mut().table.push(Descriptor)?;
        let call = store
            .run_concurrent(async |accessor| run.call_concurrent(accessor, (descriptor, 0)).await);
        let started = futures::future::poll_fn(|cx| {
            if stats
                .lock()
                .expect("read stream stats mutex poisoned")
                .method_calls
                == 1
            {
                Poll::Ready(())
            } else {
                cx.waker().wake_by_ref();
                Poll::Pending
            }
        });
        match futures::future::select(Box::pin(call), Box::pin(started)).await {
            futures::future::Either::Left((result, _started)) => {
                let result = map_wasmtime(result)?;
                let _ = map_wasmtime(result)?;
                bail!("early-drop mode completed the root task before drop");
            }
            futures::future::Either::Right((_started, pending_call)) => drop(pending_call),
        }
        drop(store);
        let snapshot = stats.lock().expect("read stream stats mutex poisoned");
        if snapshot.method_calls != 1
            || snapshot.completions != 0
            || snapshot.stream_drops != 1
            || snapshot.future_drops != 1
            || snapshot.pending_future_drops != 1
            || snapshot.descriptor_drops != 0
        {
            bail!("unexpected early-drop counters: {snapshot:?}");
        }
        println!(
            "mode={} result={} method-calls={} stream-reads={} completion-polls={} wakes={} completions={} completion-errors={} stream-drops={} future-drops={} pending-future-drops={} descriptor-drops={} table-empty=not-applicable",
            mode.label(),
            result_label(mode),
            snapshot.method_calls,
            snapshot.stream_read_calls,
            snapshot.completion_polls,
            snapshot.external_wakes,
            snapshot.completions,
            snapshot.completion_errors,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.pending_future_drops,
            snapshot.descriptor_drops
        );
        return Ok(());
    }

    if mode == Mode::Repeat {
        call_once(&mut store, run.clone()).await?;
        call_once(&mut store, run.clone()).await?;
    } else if matches!(mode, Mode::CancelBeforeEof | Mode::CancelAfterEof) {
        let cancel_export = instance
            .get_export_index(&mut store, Some(&probe), "cancel")
            .context("missing filesystem read-via-stream probe.cancel export")?;
        let cancel = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, &cancel_export))?;
        let descriptor = store.data_mut().table.push(Descriptor)?;
        let run_handle = map_wasmtime(store.spawn(RunTask {
            run,
            descriptor,
            offset: 0,
        }))?;
        if mode == Mode::CancelBeforeEof {
            map_wasmtime(map_wasmtime(
                store
                    .run_concurrent(async |_accessor| {
                        futures::future::poll_fn(|cx| {
                            if stats
                                .lock()
                                .expect("read stream stats mutex poisoned")
                                .stream_read_calls
                                == 1
                            {
                                Poll::Ready(())
                            } else {
                                cx.waker().wake_by_ref();
                                Poll::Pending
                            }
                        })
                        .await;
                        Ok::<(), wasmtime::Error>(())
                    })
                    .await,
            )?)?;
        } else {
            map_wasmtime(map_wasmtime(
                store
                    .run_concurrent(async |_accessor| {
                        futures::future::poll_fn(|cx| {
                            if stats
                                .lock()
                                .expect("read stream stats mutex poisoned")
                                .completion_polls
                                == 1
                            {
                                Poll::Ready(())
                            } else {
                                cx.waker().wake_by_ref();
                                Poll::Pending
                            }
                        })
                        .await;
                        Ok::<(), wasmtime::Error>(())
                    })
                    .await,
            )?)?;
        }
        map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |accessor| cancel.call_concurrent(accessor, ()).await)
                .await,
        )?)?;
        map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async move |_accessor| {
                    let _ = run_handle.await;
                    Ok::<(), wasmtime::Error>(())
                })
                .await,
        )?)?;
    } else {
        call_once(&mut store, run).await?;
    }

    let snapshot = stats.lock().expect("read stream stats mutex poisoned");
    if *snapshot != expected_stats(mode) || !store.data().table.is_empty() {
        bail!(
            "unexpected read-via-stream counters: expected={:?} actual={:?} table-empty={}",
            expected_stats(mode),
            *snapshot,
            store.data().table.is_empty(),
        );
    }
    println!(
        "mode={} result={} method-calls={} stream-reads={} completion-polls={} wakes={} completions={} completion-errors={} stream-drops={} future-drops={} pending-future-drops={} descriptor-drops={} table-empty=true",
        mode.label(),
        result_label(mode),
        snapshot.method_calls,
        snapshot.stream_read_calls,
        snapshot.completion_polls,
        snapshot.external_wakes,
        snapshot.completions,
        snapshot.completion_errors,
        snapshot.stream_drops,
        snapshot.future_drops,
        snapshot.pending_future_drops,
        snapshot.descriptor_drops,
    );
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-wasi-filesystem-read-via-stream-host-runner <component.wasm>")?;
    let mode = Mode::parse(
        &std::env::var("DO_READ_VIA_STREAM_MODE").unwrap_or_else(|_| "ready".to_owned()),
    )?;
    futures::executor::block_on(run(Path::new(&component_path), mode))
}
