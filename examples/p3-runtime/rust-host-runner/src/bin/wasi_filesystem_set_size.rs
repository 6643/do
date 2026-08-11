use anyhow::{Context, Result, bail};
use std::fs::OpenOptions;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Accessor, AccessorTask, Component, Linker, Resource, ResourceTable, ResourceType, TypedFunc,
};
use wasmtime::{Config, Engine, Store};

const TYPES_INSTANCE: &str = "wasi:filesystem/types@0.3.0-rc-2025-09-16";
const PROBE_INSTANCE: &str = "wasi:filesystem/probe@0.3.0-rc-2025-09-16";

pub struct Descriptor {
    path: PathBuf,
}

#[allow(dead_code)]
#[derive(
    Clone,
    Copy,
    Debug,
    PartialEq,
    Eq,
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

#[derive(Default, Clone)]
struct Stats {
    host_calls: u32,
    observed_sizes: Vec<u64>,
    mutations: u32,
    completion_polls: u32,
    external_wakes: u32,
    completions: u32,
    future_drops: u32,
    pending_future_drops: u32,
    descriptor_drops: u32,
}

struct State {
    table: ResourceTable,
    stats: Arc<Mutex<Stats>>,
}

struct RunTask {
    run: TypedFunc<(Resource<Descriptor>, u64), (std::result::Result<(), ErrorCode>,)>,
    descriptor: Resource<Descriptor>,
    size: u64,
}

impl AccessorTask<State> for RunTask {
    fn run(self, accessor: &Accessor<State>) -> impl Future<Output = wasmtime::Result<()>> + Send {
        async move {
            self.run
                .call_concurrent(accessor, (self.descriptor, self.size))
                .await
                .map(|_| ())
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Ready,
    Pending,
    Error,
    Cancel,
    EarlyDrop,
    Repeat,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "ready" => Ok(Self::Ready),
            "pending" => Ok(Self::Pending),
            "error" => Ok(Self::Error),
            "cancel" => Ok(Self::Cancel),
            "early-drop" => Ok(Self::EarlyDrop),
            "repeat" => Ok(Self::Repeat),
            other => bail!(
                "mode must be ready, pending, error, cancel, early-drop, or repeat (got {other})"
            ),
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Ready => "ready",
            Self::Pending => "pending",
            Self::Error => "error",
            Self::Cancel => "cancel",
            Self::EarlyDrop => "early-drop",
            Self::Repeat => "repeat",
        }
    }
}

struct SetSizeFuture {
    stats: Arc<Mutex<Stats>>,
    output: std::result::Result<(), ErrorCode>,
    pending_once: bool,
    never_ready: bool,
    was_pending: bool,
    completed: bool,
}

impl Future for SetSizeFuture {
    type Output = wasmtime::Result<(std::result::Result<(), ErrorCode>,)>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        {
            let mut stats = self.stats.lock().expect("set-size stats mutex poisoned");
            stats.completion_polls += 1;
        }
        if self.never_ready {
            self.was_pending = true;
            return Poll::Pending;
        }
        if self.pending_once && !self.was_pending {
            self.was_pending = true;
            self.stats
                .lock()
                .expect("set-size stats mutex poisoned")
                .external_wakes += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        self.completed = true;
        self.stats
            .lock()
            .expect("set-size stats mutex poisoned")
            .completions += 1;
        Poll::Ready(Ok((self.output,)))
    }
}

impl Drop for SetSizeFuture {
    fn drop(&mut self) {
        let mut stats = self.stats.lock().expect("set-size stats mutex poisoned");
        stats.future_drops += 1;
        if !self.completed {
            stats.pending_future_drops += 1;
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn set_file_size(path: &Path, size: u64) -> std::result::Result<(), ErrorCode> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .open(path)
        .map_err(|error| match error.kind() {
            std::io::ErrorKind::NotFound => ErrorCode::NoEntry,
            _ => ErrorCode::Io,
        })?;
    file.set_len(size).map_err(|_| ErrorCode::Io)
}

fn file_size(path: &Path) -> Result<u64> {
    Ok(std::fs::metadata(path)?.len())
}

fn snapshot(stats: &Arc<Mutex<Stats>>) -> Stats {
    stats.lock().expect("set-size stats mutex poisoned").clone()
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
    types.func_wrap_concurrent(
        "[method]descriptor.set-size",
        move |accessor, (descriptor, size): (Resource<Descriptor>, u64)| {
            let path = match accessor.with(|mut store| {
                let path = store.data_mut().table.get(&descriptor)?.path.clone();
                let mut stats = store
                    .data_mut()
                    .stats
                    .lock()
                    .expect("set-size stats mutex poisoned");
                stats.host_calls += 1;
                stats.observed_sizes.push(size);
                Ok::<PathBuf, wasmtime::Error>(path)
            }) {
                Ok(path) => path,
                Err(error) => return Box::pin(async move { Err(error) }),
            };

            let output = if mode == Mode::Error {
                Err(ErrorCode::NoEntry)
            } else {
                match set_file_size(&path, size) {
                    Ok(()) => {
                        method_stats
                            .lock()
                            .expect("set-size stats mutex poisoned")
                            .mutations += 1;
                        Ok(())
                    }
                    Err(error) => Err(error),
                }
            };
            Box::pin(SetSizeFuture {
                stats: Arc::clone(&method_stats),
                output,
                pending_once: mode == Mode::Pending,
                never_ready: mode == Mode::Cancel || mode == Mode::EarlyDrop,
                was_pending: false,
                completed: false,
            })
        },
    )?;
    Ok(())
}

async fn call_run(
    store: &mut Store<State>,
    run: TypedFunc<(Resource<Descriptor>, u64), (std::result::Result<(), ErrorCode>,)>,
    descriptor: Resource<Descriptor>,
    size: u64,
) -> Result<(std::result::Result<(), ErrorCode>,)> {
    let result = map_wasmtime(
        store
            .run_concurrent(async |accessor| {
                run.call_concurrent(accessor, (descriptor, size)).await
            })
            .await,
    )?;
    map_wasmtime(result)
}

async fn run(component_path: &Path, mode: Mode) -> Result<()> {
    let root = std::env::var_os("DO_D2_FILESYSTEM_ROOT")
        .map(PathBuf::from)
        .context("DO_D2_FILESYSTEM_ROOT is required")?;
    if !root.is_dir() || root == Path::new("/") {
        bail!("DO_D2_FILESYSTEM_ROOT must be a non-root temporary directory");
    }
    let path = root.join("file");
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
        .context("missing filesystem set-size probe export")?;
    let run_export = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing filesystem set-size probe.run export")?;
    let run = map_wasmtime(
        instance
            .get_typed_func::<(Resource<Descriptor>, u64), (std::result::Result<(), ErrorCode>,)>(
                &mut store,
                &run_export,
            ),
    )?;

    let make_descriptor = |store: &mut Store<State>| {
        store
            .data_mut()
            .table
            .push(Descriptor { path: path.clone() })
    };
    let requested_size = 4096_u64;
    let mut repeat_result = None;

    let result = match mode {
        Mode::Cancel => {
            let cancel_export = instance
                .get_export_index(&mut store, Some(&probe), "cancel")
                .context("missing filesystem set-size probe.cancel export")?;
            let cancel =
                map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, &cancel_export))?;
            let descriptor = make_descriptor(&mut store)?;
            let run_handle = map_wasmtime(store.spawn(RunTask {
                run,
                descriptor,
                size: requested_size,
            }))?;
            map_wasmtime(map_wasmtime(
                store
                    .run_concurrent(async |_accessor| {
                        futures::future::poll_fn(|cx| {
                            let current = snapshot(&stats);
                            if current.host_calls == 1 && current.completion_polls == 1 {
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
            let cancelled = map_wasmtime(
                store
                    .run_concurrent(async |accessor| cancel.call_concurrent(accessor, ()).await)
                    .await,
            )?;
            map_wasmtime(cancelled)?;
            map_wasmtime(map_wasmtime(
                store
                    .run_concurrent(async move |_accessor| {
                        let _ = run_handle.await;
                        Ok::<(), wasmtime::Error>(())
                    })
                    .await,
            )?)?;
            None
        }
        Mode::EarlyDrop => {
            let descriptor = make_descriptor(&mut store)?;
            let call = store.run_concurrent(async |accessor| {
                run.call_concurrent(accessor, (descriptor, requested_size))
                    .await
            });
            let started = futures::future::poll_fn(|cx| {
                let current = snapshot(&stats);
                if current.host_calls == 1 {
                    Poll::Ready(())
                } else {
                    cx.waker().wake_by_ref();
                    Poll::Pending
                }
            });
            let early_drop_ready = {
                let selected = futures::future::select(Box::pin(call), Box::pin(started)).await;
                match selected {
                    futures::future::Either::Left((result, _started)) => {
                        let result = map_wasmtime(result)?;
                        let _ = map_wasmtime(result)?;
                        bail!("early-drop mode completed the root task before drop");
                    }
                    futures::future::Either::Right((_started, pending_call)) => {
                        drop(pending_call);
                        true
                    }
                }
            };
            if early_drop_ready {
                drop(store);
                let current = snapshot(&stats);
                if current.host_calls != 1
                    || current.completions != 0
                    || current.future_drops != 1
                    || current.pending_future_drops != 1
                    || current.descriptor_drops != 0
                    || file_size(&path)? != requested_size
                {
                    bail!(
                        "unexpected set-size early-drop: host-calls={} completions={} future-drops={} pending-future-drops={} descriptor-drops={} file-size={}",
                        current.host_calls,
                        current.completions,
                        current.future_drops,
                        current.pending_future_drops,
                        current.descriptor_drops,
                        file_size(&path)?,
                    );
                }
                println!(
                    "mode=early-drop result=store-discarded host-calls={} observed-sizes={:?} mutations={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} descriptor-drops={} file-size={} table-empty=not-applicable",
                    current.host_calls,
                    current.observed_sizes,
                    current.mutations,
                    current.completion_polls,
                    current.external_wakes,
                    current.completions,
                    current.future_drops,
                    current.pending_future_drops,
                    current.descriptor_drops,
                    file_size(&path)?,
                );
                return Ok(());
            }
            None
        }
        Mode::Repeat => {
            let first_descriptor = make_descriptor(&mut store)?;
            let first = call_run(&mut store, run, first_descriptor, requested_size).await?;
            let second_size = requested_size + 1;
            let second_descriptor = make_descriptor(&mut store)?;
            let second = call_run(&mut store, run, second_descriptor, second_size).await?;
            repeat_result = Some((first, second));
            None
        }
        Mode::Ready | Mode::Pending | Mode::Error => {
            let descriptor = make_descriptor(&mut store)?;
            Some(call_run(&mut store, run, descriptor, requested_size).await?)
        }
    };

    let current = snapshot(&stats);
    let table_empty = store.data().table.is_empty();
    if !table_empty {
        bail!("unexpected set-size ResourceTable contents at terminal state");
    }
    match mode {
        Mode::Ready | Mode::Pending => {
            let (value,) = result.context("missing set-size result")?;
            if value != Ok(()) || file_size(&path)? != requested_size {
                bail!(
                    "unexpected set-size success: value={value:?} file-size={}",
                    file_size(&path)?
                );
            }
            println!(
                "mode={} result=Ok host-calls={} observed-sizes={:?} mutations={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} descriptor-drops={} file-size={} table-empty=true",
                mode.label(),
                current.host_calls,
                current.observed_sizes,
                current.mutations,
                current.completion_polls,
                current.external_wakes,
                current.completions,
                current.future_drops,
                current.pending_future_drops,
                current.descriptor_drops,
                file_size(&path)?,
            );
        }
        Mode::Error => {
            let (value,) = result.context("missing set-size error result")?;
            if value != Err(ErrorCode::NoEntry) || current.mutations != 0 {
                bail!(
                    "unexpected set-size error: value={value:?} mutations={}",
                    current.mutations
                );
            }
            println!(
                "mode=error result=Err(no-entry) host-calls={} observed-sizes={:?} mutations={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} descriptor-drops={} file-size={} table-empty=true",
                current.host_calls,
                current.observed_sizes,
                current.mutations,
                current.completion_polls,
                current.external_wakes,
                current.completions,
                current.future_drops,
                current.pending_future_drops,
                current.descriptor_drops,
                file_size(&path)?,
            );
        }
        Mode::Cancel => {
            if current.completions != 0
                || current.pending_future_drops != 1
                || current.descriptor_drops != 1
                || current.mutations != 1
                || file_size(&path)? != requested_size
            {
                bail!(
                    "unexpected set-size cancellation: stats={:?} file-size={}",
                    current.mutations,
                    file_size(&path)?
                );
            }
            println!(
                "mode=cancel result=cancelled host-calls={} observed-sizes={:?} mutations={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} descriptor-drops={} file-size={} table-empty=true",
                current.host_calls,
                current.observed_sizes,
                current.mutations,
                current.completion_polls,
                current.external_wakes,
                current.completions,
                current.future_drops,
                current.pending_future_drops,
                current.descriptor_drops,
                file_size(&path)?,
            );
        }
        Mode::EarlyDrop => unreachable!("early-drop returns after Store disposal"),
        Mode::Repeat => {
            let (first, second) = repeat_result.context("missing repeat results")?;
            if first.0 != Ok(())
                || second.0 != Ok(())
                || current.mutations != 2
                || current.descriptor_drops != 2
                || file_size(&path)? != requested_size + 1
            {
                bail!("unexpected set-size repeat: first={first:?} second={second:?}");
            }
            println!(
                "mode=repeat results=Ok,Ok host-calls={} observed-sizes={:?} mutations={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} descriptor-drops={} file-size={} table-empty=true",
                current.host_calls,
                current.observed_sizes,
                current.mutations,
                current.completion_polls,
                current.external_wakes,
                current.completions,
                current.future_drops,
                current.pending_future_drops,
                current.descriptor_drops,
                file_size(&path)?,
            );
        }
    }
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: wasi-filesystem-set-size <component.wasm> <mode>")?;
    let mode = args
        .next()
        .context("usage: wasi-filesystem-set-size <component.wasm> <mode>")?;
    if args.next().is_some() {
        bail!("usage: wasi-filesystem-set-size <component.wasm> <mode>");
    }
    futures::executor::block_on(run(Path::new(&component_path), Mode::parse(&mode)?))
}
