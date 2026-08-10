use anyhow::{Context, Result, bail};
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
enum DescriptorType {
    #[component(name = "unknown")]
    Unknown,
    #[component(name = "block-device")]
    BlockDevice,
    #[component(name = "character-device")]
    CharacterDevice,
    #[component(name = "directory")]
    Directory,
    #[component(name = "fifo")]
    Fifo,
    #[component(name = "symbolic-link")]
    SymbolicLink,
    #[component(name = "regular-file")]
    RegularFile,
    #[component(name = "socket")]
    Socket,
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
#[component(record)]
struct Datetime {
    seconds: u64,
    nanoseconds: u32,
}

#[derive(
    Clone,
    Debug,
    PartialEq,
    Eq,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(record)]
struct DescriptorStat {
    #[component(name = "type")]
    type_: DescriptorType,
    #[component(name = "link-count")]
    link_count: u64,
    size: u64,
    #[component(name = "data-access-timestamp")]
    data_access_timestamp: Option<Datetime>,
    #[component(name = "data-modification-timestamp")]
    data_modification_timestamp: Option<Datetime>,
    #[component(name = "status-change-timestamp")]
    status_change_timestamp: Option<Datetime>,
}

#[derive(Default, Clone, Copy)]
struct Stats {
    host_calls: u32,
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
    run: TypedFunc<(Resource<Descriptor>,), (std::result::Result<DescriptorStat, ErrorCode>,)>,
    descriptor: Resource<Descriptor>,
}

impl AccessorTask<State> for RunTask {
    fn run(self, accessor: &Accessor<State>) -> impl Future<Output = wasmtime::Result<()>> + Send {
        async move {
            self.run
                .call_concurrent(accessor, (self.descriptor,))
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

struct StatFuture {
    stats: Arc<Mutex<Stats>>,
    output: std::result::Result<DescriptorStat, ErrorCode>,
    pending_once: bool,
    never_ready: bool,
    was_pending: bool,
    completed: bool,
}

impl Future for StatFuture {
    type Output = wasmtime::Result<(std::result::Result<DescriptorStat, ErrorCode>,)>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        {
            let mut stats = self.stats.lock().expect("stat stats mutex poisoned");
            stats.completion_polls += 1;
        }
        if self.never_ready {
            self.was_pending = true;
            return Poll::Pending;
        }
        if self.pending_once && !self.was_pending {
            self.was_pending = true;
            let mut stats = self.stats.lock().expect("stat stats mutex poisoned");
            stats.external_wakes += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        self.completed = true;
        let mut stats = self.stats.lock().expect("stat stats mutex poisoned");
        stats.completions += 1;
        Poll::Ready(Ok((self.output.clone(),)))
    }
}

impl Drop for StatFuture {
    fn drop(&mut self) {
        let mut stats = self.stats.lock().expect("stat stats mutex poisoned");
        stats.future_drops += 1;
        if !self.completed {
            stats.pending_future_drops += 1;
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn expected_stat() -> DescriptorStat {
    DescriptorStat {
        type_: DescriptorType::RegularFile,
        link_count: 1,
        size: 4096,
        data_access_timestamp: Some(Datetime {
            seconds: 100,
            nanoseconds: 1,
        }),
        data_modification_timestamp: Some(Datetime {
            seconds: 101,
            nanoseconds: 2,
        }),
        status_change_timestamp: Some(Datetime {
            seconds: 102,
            nanoseconds: 3,
        }),
    }
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
        "[method]descriptor.stat",
        move |accessor, (descriptor,): (Resource<Descriptor>,)| {
            let path = match accessor.with(|mut store| {
                let path = store.data_mut().table.get(&descriptor)?.path.clone();
                store
                    .data_mut()
                    .stats
                    .lock()
                    .expect("stat stats mutex poisoned")
                    .host_calls += 1;
                Ok::<PathBuf, wasmtime::Error>(path)
            }) {
                Ok(path) => path,
                Err(error) => return Box::pin(async move { Err(error) }),
            };
            let output = if mode == Mode::Error || !path.exists() {
                Err(ErrorCode::NoEntry)
            } else {
                Ok(expected_stat())
            };
            Box::pin(StatFuture {
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
    run: TypedFunc<(Resource<Descriptor>,), (std::result::Result<DescriptorStat, ErrorCode>,)>,
    descriptor: Resource<Descriptor>,
) -> Result<(std::result::Result<DescriptorStat, ErrorCode>,)> {
    let result = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(accessor, (descriptor,)).await)
            .await,
    )?;
    map_wasmtime(result)
}

fn check_stat(value: &std::result::Result<DescriptorStat, ErrorCode>) -> bool {
    value.as_ref() == Ok(&expected_stat())
}

async fn run(component_path: &Path, mode: Mode) -> Result<()> {
    let root = std::env::var_os("DO_D2_FILESYSTEM_ROOT")
        .map(PathBuf::from)
        .context("DO_D2_FILESYSTEM_ROOT is required")?;
    if !root.is_dir() || root == Path::new("/") {
        bail!("DO_D2_FILESYSTEM_ROOT must be a non-root temporary directory");
    }

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
        .context("missing filesystem probe export")?;
    let run_export = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing filesystem probe.run export")?;
    let run = map_wasmtime(instance.get_typed_func::<
        (Resource<Descriptor>,),
        (std::result::Result<DescriptorStat, ErrorCode>,),
    >(&mut store, &run_export))?;

    let descriptor_path = root.join("file");
    let make_descriptor = |store: &mut Store<State>| {
        store.data_mut().table.push(Descriptor {
            path: descriptor_path.clone(),
        })
    };

    let mut repeat_result = None;
    let result = match mode {
        Mode::Cancel => {
            let cancel_export = instance
                .get_export_index(&mut store, Some(&probe), "cancel")
                .context("missing filesystem probe.cancel export")?;
            let cancel =
                map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, &cancel_export))?;
            let descriptor = make_descriptor(&mut store)?;
            let run_handle = map_wasmtime(store.spawn(RunTask { run, descriptor }))?;
            map_wasmtime(map_wasmtime(
                store
                    .run_concurrent(async |_accessor| {
                        futures::future::poll_fn(|cx| {
                            let snapshot = *stats.lock().expect("stat stats mutex poisoned");
                            if snapshot.host_calls == 1 && snapshot.completion_polls == 1 {
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
                        run_handle.await;
                        Ok::<(), wasmtime::Error>(())
                    })
                    .await,
            )?)?;
            None
        }
        Mode::EarlyDrop => {
            let descriptor = make_descriptor(&mut store)?;
            let call = store.run_concurrent(async |accessor| {
                run.call_concurrent(accessor, (descriptor,)).await
            });
            let started = futures::future::poll_fn(|cx| {
                let snapshot = *stats.lock().expect("stat stats mutex poisoned");
                if snapshot.host_calls == 1 {
                    Poll::Ready(())
                } else {
                    cx.waker().wake_by_ref();
                    Poll::Pending
                }
            });
            let dropped = match futures::future::select(Box::pin(call), Box::pin(started)).await {
                futures::future::Either::Left((result, _started)) => {
                    let result = map_wasmtime(result)?;
                    let _ = map_wasmtime(result)?;
                    bail!("early-drop mode completed the root task before drop");
                }
                futures::future::Either::Right((_started, pending_call)) => {
                    drop(pending_call);
                    true
                }
            };
            if dropped {
                drop(store);
                let snapshot = *stats.lock().expect("stat stats mutex poisoned");
                if snapshot.host_calls != 1
                    || snapshot.completion_polls != 2
                    || snapshot.completions != 0
                    || snapshot.future_drops != 1
                    || snapshot.pending_future_drops != 1
                    || snapshot.descriptor_drops != 0
                {
                    bail!(
                        "unexpected stat early-drop store disposal: host-calls={} completion-polls={} completions={} future-drops={} pending-future-drops={} descriptor-drops={}",
                        snapshot.host_calls,
                        snapshot.completion_polls,
                        snapshot.completions,
                        snapshot.future_drops,
                        snapshot.pending_future_drops,
                        snapshot.descriptor_drops,
                    );
                }
                println!(
                    "mode=early-drop result=store-discarded host-calls={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} descriptor-drops={} table-empty=not-applicable",
                    snapshot.host_calls,
                    snapshot.completion_polls,
                    snapshot.external_wakes,
                    snapshot.completions,
                    snapshot.future_drops,
                    snapshot.pending_future_drops,
                    snapshot.descriptor_drops,
                );
                return Ok(());
            }
            unreachable!("early-drop select did not yield a drop path")
        }
        Mode::Repeat => {
            let first_descriptor = make_descriptor(&mut store)?;
            let first = call_run(&mut store, run, first_descriptor).await?;
            let second_descriptor = make_descriptor(&mut store)?;
            let second = call_run(&mut store, run, second_descriptor).await?;
            repeat_result = Some((first, second));
            None
        }
        Mode::Ready | Mode::Pending | Mode::Error => {
            let descriptor = make_descriptor(&mut store)?;
            Some(call_run(&mut store, run, descriptor).await?)
        }
    };

    let snapshot = *stats.lock().expect("stat stats mutex poisoned");
    let table_empty = store.data().table.is_empty();
    if !table_empty {
        bail!("unexpected stat ResourceTable contents at terminal state");
    }

    match mode {
        Mode::Ready | Mode::Pending => {
            let (value,) = result.context("missing stat result")?;
            if !check_stat(&value) {
                bail!("unexpected stat result: {value:?}");
            }
            println!(
                "mode={} result=Ok descriptor-type=regular-file link-count=1 size=4096 access=Some(100,1) modification=Some(101,2) change=Some(102,3) host-calls={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} descriptor-drops={} table-empty=true",
                mode.label(),
                snapshot.host_calls,
                snapshot.completion_polls,
                snapshot.external_wakes,
                snapshot.completions,
                snapshot.future_drops,
                snapshot.pending_future_drops,
                snapshot.descriptor_drops,
            );
        }
        Mode::Error => {
            let (value,) = result.context("missing stat result")?;
            if value != Err(ErrorCode::NoEntry) {
                bail!("unexpected stat error result: {value:?}");
            }
            println!(
                "mode=error result=Err(no-entry) options=none host-calls={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} descriptor-drops={} table-empty=true",
                snapshot.host_calls,
                snapshot.completion_polls,
                snapshot.external_wakes,
                snapshot.completions,
                snapshot.future_drops,
                snapshot.pending_future_drops,
                snapshot.descriptor_drops,
            );
        }
        Mode::Cancel => {
            if snapshot.completions != 0 || snapshot.pending_future_drops != 1 {
                bail!(
                    "unexpected stat cancellation: completions={} pending-future-drops={}",
                    snapshot.completions,
                    snapshot.pending_future_drops,
                );
            }
            println!(
                "mode=cancel result=cancelled host-calls={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} descriptor-drops={} table-empty=true",
                snapshot.host_calls,
                snapshot.completion_polls,
                snapshot.external_wakes,
                snapshot.completions,
                snapshot.future_drops,
                snapshot.pending_future_drops,
                snapshot.descriptor_drops,
            );
        }
        Mode::EarlyDrop => unreachable!("early-drop returns after Store disposal"),
        Mode::Repeat => {
            let (first, second) = repeat_result.context("missing repeat results")?;
            if !check_stat(&first.0) || !check_stat(&second.0) {
                bail!("unexpected repeat stat results: {first:?}, {second:?}");
            }
            println!(
                "mode=repeat results=Ok,Ok host-calls={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} descriptor-drops={} table-empty=true",
                snapshot.host_calls,
                snapshot.completion_polls,
                snapshot.external_wakes,
                snapshot.completions,
                snapshot.future_drops,
                snapshot.pending_future_drops,
                snapshot.descriptor_drops,
            );
        }
    }
    if snapshot.descriptor_drops
        != match mode {
            Mode::Repeat => 2,
            _ => 1,
        }
    {
        bail!(
            "unexpected descriptor drop count: {}",
            snapshot.descriptor_drops
        );
    }
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: do-p3-wasi-filesystem-stat-host-runner <component.wasm> <mode>")?;
    let mode = args
        .next()
        .context("usage: do-p3-wasi-filesystem-stat-host-runner <component.wasm> <mode>")?;
    if args.next().is_some() {
        bail!("usage: do-p3-wasi-filesystem-stat-host-runner <component.wasm> <mode>");
    }
    futures::executor::block_on(run(Path::new(&component_path), Mode::parse(&mode)?))
}
