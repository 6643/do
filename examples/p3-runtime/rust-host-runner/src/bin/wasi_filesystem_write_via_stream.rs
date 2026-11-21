use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Linker, Resource, ResourceTable, ResourceType, Source, StreamConsumer, StreamReader,
    StreamResult, TypedFunc,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const TYPES_INSTANCE: &str = "wasi:filesystem/types@0.3.0-rc-2025-09-16";
const PROBE_INSTANCE: &str = "wasi:filesystem/probe@0.3.0-rc-2025-09-16";

#[derive(Debug)]
struct Descriptor;

#[allow(dead_code)]
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
enum ErrorCode {
    #[component(name = "access")]
    Access,
    #[component(name = "already")]
    Already,
    #[component(name = "bad-descriptor")]
    BadDescriptor,
    #[component(name = "busy")]
    Busy,
    #[component(name = "deadlock")]
    Deadlock,
    #[component(name = "quota")]
    Quota,
    #[component(name = "exist")]
    Exist,
    #[component(name = "file-too-large")]
    FileTooLarge,
    #[component(name = "illegal-byte-sequence")]
    IllegalByteSequence,
    #[component(name = "in-progress")]
    InProgress,
    #[component(name = "interrupted")]
    Interrupted,
    #[component(name = "invalid")]
    Invalid,
    #[component(name = "io")]
    Io,
    #[component(name = "is-directory")]
    IsDirectory,
    #[component(name = "loop")]
    Loop,
    #[component(name = "too-many-links")]
    TooManyLinks,
    #[component(name = "message-size")]
    MessageSize,
    #[component(name = "name-too-long")]
    NameTooLong,
    #[component(name = "no-device")]
    NoDevice,
    #[component(name = "no-entry")]
    NoEntry,
    #[component(name = "no-lock")]
    NoLock,
    #[component(name = "insufficient-memory")]
    InsufficientMemory,
    #[component(name = "insufficient-space")]
    InsufficientSpace,
    #[component(name = "not-directory")]
    NotDirectory,
    #[component(name = "not-empty")]
    NotEmpty,
    #[component(name = "not-recoverable")]
    NotRecoverable,
    #[component(name = "unsupported")]
    Unsupported,
    #[component(name = "no-tty")]
    NoTty,
    #[component(name = "no-such-device")]
    NoSuchDevice,
    #[component(name = "overflow")]
    Overflow,
    #[component(name = "not-permitted")]
    NotPermitted,
    #[component(name = "pipe")]
    Pipe,
    #[component(name = "read-only")]
    ReadOnly,
    #[component(name = "invalid-seek")]
    InvalidSeek,
    #[component(name = "text-file-busy")]
    TextFileBusy,
    #[component(name = "cross-device")]
    CrossDevice,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Ready,
    Pending,
    SinkError,
    MethodError,
    CancelBeforeCompletion,
    CancelAfterClose,
    EarlyDrop,
    Repeat,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "ready" => Ok(Self::Ready),
            "pending" => Ok(Self::Pending),
            "sink-error" => Ok(Self::SinkError),
            "method-error" => Ok(Self::MethodError),
            "cancel-before-completion" => Ok(Self::CancelBeforeCompletion),
            "cancel-after-close" => Ok(Self::CancelAfterClose),
            "early-drop" => Ok(Self::EarlyDrop),
            "repeat" => Ok(Self::Repeat),
            other => bail!("unknown mode {other}"),
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Ready => "ready",
            Self::Pending => "pending",
            Self::SinkError => "sink-error",
            Self::MethodError => "method-error",
            Self::CancelBeforeCompletion => "cancel-before-completion",
            Self::CancelAfterClose => "cancel-after-close",
            Self::EarlyDrop => "early-drop",
            Self::Repeat => "repeat",
        }
    }
}

#[derive(Default, Debug)]
struct Stats {
    method_calls: u32,
    offsets: Vec<u64>,
    bytes: Vec<u8>,
    stream_polls: u32,
    external_wakes: u32,
    stream_drops: u32,
    method_completions: u32,
    method_errors: u32,
    descriptor_drops: u32,
}

struct State {
    table: ResourceTable,
    stats: Arc<Mutex<Stats>>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ConsumerOutcome {
    Completed,
    Failed,
    Cancelled,
}

struct WriterConsumer {
    stats: Arc<Mutex<Stats>>,
    pending_once: bool,
    never_ready: bool,
    polled: bool,
    fail: bool,
    outcome: Option<oneshot::Sender<ConsumerOutcome>>,
}

impl WriterConsumer {
    fn signal(&mut self, outcome: ConsumerOutcome) {
        if let Some(sender) = self.outcome.take() {
            let _ = sender.send(outcome);
        }
    }
}

impl StreamConsumer<State> for WriterConsumer {
    type Item = u8;

    fn poll_consume(
        mut self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'_, State>,
        mut source: Source<'_, Self::Item>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        self.stats
            .lock()
            .expect("writer stats poisoned")
            .stream_polls += 1;
        if finish {
            self.signal(ConsumerOutcome::Cancelled);
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }
        if self.pending_once && !self.polled {
            self.polled = true;
            self.stats
                .lock()
                .expect("writer stats poisoned")
                .external_wakes += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        if self.never_ready {
            return Poll::Pending;
        }
        let remaining = source.remaining(&mut store);
        if remaining == 0 {
            return Poll::Pending;
        }
        let mut bytes = Vec::with_capacity(remaining);
        source.read(&mut store, &mut bytes)?;
        self.stats
            .lock()
            .expect("writer stats poisoned")
            .bytes
            .extend_from_slice(&bytes);
        if self.fail {
            self.signal(ConsumerOutcome::Failed);
            return Poll::Ready(Err(wasmtime::Error::msg("controlled sink error")));
        }
        self.signal(ConsumerOutcome::Completed);
        Poll::Ready(Ok(StreamResult::Dropped))
    }
}

impl Drop for WriterConsumer {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("writer stats poisoned")
            .stream_drops += 1;
        self.signal(ConsumerOutcome::Cancelled);
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
            let resource = Resource::<Descriptor>::new_own(rep);
            store.data_mut().table.delete(resource)?;
            store
                .data()
                .stats
                .lock()
                .expect("writer stats poisoned")
                .descriptor_drops += 1;
            Ok(())
        },
    )?;

    let method_stats = Arc::clone(&stats);
    types.func_wrap_concurrent(
        "[method]descriptor.write-via-stream",
        move |accessor,
              (descriptor, reader, offset): (Resource<Descriptor>, StreamReader<u8>, u64)| {
            let stats = Arc::clone(&method_stats);
            Box::pin(async move {
                let receiver = accessor.with(|mut store| {
                    let _ = store.data_mut().table.get(&descriptor)?;
                    let mut snapshot = stats.lock().expect("writer stats poisoned");
                    snapshot.method_calls += 1;
                    snapshot.offsets.push(offset);
                    let (sender, receiver) = oneshot::channel();
                    reader.pipe(
                        &mut store,
                        WriterConsumer {
                            stats: Arc::clone(&stats),
                            pending_once: matches!(
                                mode,
                                Mode::Pending | Mode::CancelBeforeCompletion | Mode::EarlyDrop
                            ),
                            never_ready: matches!(
                                mode,
                                Mode::CancelBeforeCompletion | Mode::EarlyDrop
                            ),
                            polled: false,
                            fail: mode == Mode::SinkError,
                            outcome: Some(sender),
                        },
                    )?;
                    Ok::<_, wasmtime::Error>(receiver)
                })?;
                let outcome = receiver
                    .await
                    .map_err(|_| wasmtime::Error::msg("writer consumer dropped"))?;
                match outcome {
                    ConsumerOutcome::Failed => {
                        stats.lock().expect("writer stats poisoned").method_errors += 1;
                        Ok((Err(ErrorCode::Io),))
                    }
                    ConsumerOutcome::Cancelled => {
                        Err(wasmtime::Error::msg("writer cancelled before completion"))
                    }
                    ConsumerOutcome::Completed if mode == Mode::MethodError => {
                        stats.lock().expect("writer stats poisoned").method_errors += 1;
                        Ok((Err(ErrorCode::Io),))
                    }
                    ConsumerOutcome::Completed => {
                        stats
                            .lock()
                            .expect("writer stats poisoned")
                            .method_completions += 1;
                        if mode == Mode::CancelAfterClose {
                            std::future::pending::<
                                wasmtime::Result<(std::result::Result<(), ErrorCode>,)>,
                            >()
                            .await
                        } else {
                            Ok((Ok(()),))
                        }
                    }
                }
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
    let result = map_wasmtime(run.call_async(store, (descriptor, 1234)).await);
    result
}

async fn run(component_path: &Path, mode: Mode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.wasm_gc(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))?;
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
        .context("missing write probe")?;
    let run_export = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing run")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(Resource<Descriptor>, u64), ()>(&mut store, &run_export),
    )?;

    if mode == Mode::EarlyDrop {
        let descriptor = store.data_mut().table.push(Descriptor)?;
        let call = store.run_concurrent(async |accessor| {
            run.call_concurrent(accessor, (descriptor, 1234)).await
        });
        let started = futures::future::poll_fn(|cx| {
            if stats.lock().expect("writer stats poisoned").method_calls == 1 {
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
        print_stats(mode, &stats, false)?;
        return Ok(());
    }

    if mode == Mode::Repeat {
        call_once(&mut store, run.clone()).await?;
        call_once(&mut store, run.clone()).await?;
    } else if matches!(mode, Mode::CancelBeforeCompletion | Mode::CancelAfterClose) {
        let cancel_export = instance
            .get_export_index(&mut store, Some(&probe), "cancel")
            .context("missing cancel")?;
        let cancel = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, &cancel_export))?;
        let descriptor = store.data_mut().table.push(Descriptor)?;
        let handle =
            map_wasmtime(store.spawn(async move |accessor| {
                run.call_concurrent(accessor, (descriptor, 1234)).await
            }))?;
        map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |_accessor| {
                    futures::future::poll_fn(|cx| {
                        let snapshot = stats.lock().expect("writer stats poisoned");
                        let ready = match mode {
                            Mode::CancelBeforeCompletion => snapshot.method_calls == 1,
                            Mode::CancelAfterClose => {
                                snapshot.stream_drops == 1 && snapshot.method_completions == 1
                            }
                            _ => false,
                        };
                        if ready {
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
        map_wasmtime(
            store
                .run_concurrent(async |accessor| cancel.call_concurrent(accessor, ()).await)
                .await,
        )?
        .map_err(|error| anyhow::anyhow!("{error:#}"))?;
        map_wasmtime(
            store
                .run_concurrent(async move |_accessor| {
                    let _ = handle.await;
                    Ok::<(), wasmtime::Error>(())
                })
                .await,
        )?
        .map_err(|error| anyhow::anyhow!("{error:#}"))?;
    } else if mode == Mode::SinkError {
        let result = call_once(&mut store, run).await;
        if result.is_ok() {
            bail!("sink-error mode completed the run successfully");
        }
        drop(store);
        let snapshot = stats.lock().expect("writer stats poisoned");
        if snapshot.bytes != vec![65]
            || snapshot.stream_drops != 1
            || snapshot.method_completions != 0
            || snapshot.descriptor_drops != 0
        {
            bail!("unexpected sink-error disposal snapshot: {snapshot:?}");
        }
        println!(
            "mode=sink-error result=trap offsets={:?} bytes={:?} method-calls={} stream-polls={} wakes={} stream-drops={} method-completions={} method-errors={} descriptor-drops={} table-empty=not-applicable",
            snapshot.offsets,
            snapshot.bytes,
            snapshot.method_calls,
            snapshot.stream_polls,
            snapshot.external_wakes,
            snapshot.stream_drops,
            snapshot.method_completions,
            snapshot.method_errors,
            snapshot.descriptor_drops,
        );
        return Ok(());
    } else {
        call_once(&mut store, run).await?;
    }

    print_stats(mode, &stats, store.data().table.is_empty())?;
    Ok(())
}

fn print_stats(mode: Mode, stats: &Arc<Mutex<Stats>>, table_empty: bool) -> Result<()> {
    let snapshot = stats.lock().expect("writer stats poisoned");
    let expected_runs = u32::from(mode == Mode::Repeat) + 1;
    let expected_bytes = match mode {
        Mode::CancelBeforeCompletion | Mode::EarlyDrop => Vec::new(),
        _ if mode == Mode::Repeat => vec![65, 65],
        _ => vec![65],
    };
    let expected_completions = match mode {
        Mode::Ready | Mode::Pending | Mode::CancelAfterClose => 1,
        Mode::Repeat => 2,
        _ => 0,
    };
    let expected_errors = u32::from(matches!(mode, Mode::SinkError | Mode::MethodError));
    let expected_descriptor_drops = u32::from(mode != Mode::EarlyDrop) * expected_runs;
    if snapshot.offsets.iter().any(|offset| *offset != 1234)
        || snapshot.bytes != expected_bytes
        || snapshot.stream_drops != expected_runs
        || snapshot.method_completions != expected_completions
        || snapshot.method_errors != expected_errors
        || snapshot.descriptor_drops != expected_descriptor_drops
        || mode != Mode::EarlyDrop && !table_empty
    {
        bail!("unexpected writer lifecycle snapshot: {snapshot:?}");
    }
    let result_label = if mode == Mode::EarlyDrop {
        " result=store-discarded"
    } else {
        ""
    };
    println!(
        "mode={}{} offsets={:?} bytes={:?} method-calls={} stream-polls={} wakes={} stream-drops={} method-completions={} method-errors={} descriptor-drops={} table-empty={}",
        mode.label(),
        result_label,
        snapshot.offsets,
        snapshot.bytes,
        snapshot.method_calls,
        snapshot.stream_polls,
        snapshot.external_wakes,
        snapshot.stream_drops,
        snapshot.method_completions,
        snapshot.method_errors,
        snapshot.descriptor_drops,
        table_empty,
    );
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: wasi-filesystem-write-via-stream <component.wasm>")?;
    let mode = Mode::parse(
        &std::env::var("DO_WRITE_VIA_STREAM_MODE").unwrap_or_else(|_| "ready".to_owned()),
    )?;
    futures::executor::block_on(run(Path::new(&component_path), mode))
}
