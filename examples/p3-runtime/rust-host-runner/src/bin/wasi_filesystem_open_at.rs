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

#[derive(Clone, Debug)]
pub struct Descriptor {
    path: PathBuf,
    is_dir: bool,
}

wasmtime::component::flags! {
    PathFlags {
        #[component(name = "symlink-follow")]
        const SYMLINK_FOLLOW;
    }
}

wasmtime::component::flags! {
    OpenFlags {
        #[component(name = "create")]
        const CREATE;
        #[component(name = "directory")]
        const DIRECTORY;
        #[component(name = "exclusive")]
        const EXCLUSIVE;
        #[component(name = "truncate")]
        const TRUNCATE;
    }
}

wasmtime::component::flags! {
    DescriptorFlags {
        #[component(name = "read")]
        const READ;
        #[component(name = "write")]
        const WRITE;
        #[component(name = "file-integrity-sync")]
        const FILE_INTEGRITY_SYNC;
        #[component(name = "data-integrity-sync")]
        const DATA_INTEGRITY_SYNC;
        #[component(name = "requested-write-sync")]
        const REQUESTED_WRITE_SYNC;
        #[component(name = "mutate-directory")]
        const MUTATE_DIRECTORY;
    }
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
    path_copies: u32,
    observed_path: Option<String>,
    observed_path_flags: Option<u32>,
    observed_open_flags: Option<u32>,
    observed_descriptor_flags: Option<u32>,
    completion_polls: u32,
    external_wakes: u32,
    completions: u32,
    future_drops: u32,
    pending_future_drops: u32,
    parent_drops: u32,
    child_drops: u32,
    child_created: u32,
}

struct State {
    table: ResourceTable,
    stats: Arc<Mutex<Stats>>,
}

type OpenResult = std::result::Result<Resource<Descriptor>, ErrorCode>;
type OpenOutput = wasmtime::Result<(OpenResult,)>;
type RunFunc = TypedFunc<
    (
        Resource<Descriptor>,
        PathFlags,
        String,
        OpenFlags,
        DescriptorFlags,
    ),
    (OpenResult,),
>;

struct RunTask {
    run: RunFunc,
    descriptor: Resource<Descriptor>,
    path_flags: PathFlags,
    path: String,
    open_flags: OpenFlags,
    descriptor_flags: DescriptorFlags,
}

impl AccessorTask<State> for RunTask {
    fn run(self, accessor: &Accessor<State>) -> impl Future<Output = wasmtime::Result<()>> + Send {
        async move {
            self.run
                .call_concurrent(
                    accessor,
                    (
                        self.descriptor,
                        self.path_flags,
                        self.path,
                        self.open_flags,
                        self.descriptor_flags,
                    ),
                )
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

struct OpenFuture<'a> {
    accessor: &'a Accessor<State>,
    stats: Arc<Mutex<Stats>>,
    parent_path: PathBuf,
    path: String,
    path_flags: PathFlags,
    open_flags: OpenFlags,
    descriptor_flags: DescriptorFlags,
    output_error: bool,
    pending_once: bool,
    never_ready: bool,
    was_pending: bool,
    completed: bool,
}

impl Future for OpenFuture<'_> {
    type Output = OpenOutput;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        {
            let mut stats = self.stats.lock().expect("open-at stats mutex poisoned");
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
                .expect("open-at stats mutex poisoned")
                .external_wakes += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }

        {
            let mut stats = self.stats.lock().expect("open-at stats mutex poisoned");
            stats.observed_path = Some(self.path.clone());
            stats.observed_path_flags =
                Some(if self.path_flags.contains(PathFlags::SYMLINK_FOLLOW) {
                    1
                } else {
                    0
                });
            stats.observed_open_flags = Some(open_flags_bits(self.open_flags));
            stats.observed_descriptor_flags = Some(descriptor_flags_bits(self.descriptor_flags));
            stats.completions += 1;
        }
        if self.output_error {
            self.completed = true;
            return Poll::Ready(Ok((Err(ErrorCode::NoEntry),)));
        }

        let child_path = self.parent_path.join(&self.path);
        let child = match self.accessor.with(|mut access| {
            let child = access.data_mut().table.push(Descriptor {
                path: child_path,
                is_dir: false,
            })?;
            access
                .data_mut()
                .stats
                .lock()
                .expect("open-at stats mutex poisoned")
                .child_created += 1;
            Ok::<Resource<Descriptor>, wasmtime::Error>(child)
        }) {
            Ok(child) => child,
            Err(error) => return Poll::Ready(Err(error)),
        };
        self.completed = true;
        Poll::Ready(Ok((Ok(child),)))
    }
}

impl Drop for OpenFuture<'_> {
    fn drop(&mut self) {
        let mut stats = self.stats.lock().expect("open-at stats mutex poisoned");
        stats.future_drops += 1;
        if !self.completed {
            stats.pending_future_drops += 1;
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn open_flags_bits(flags: OpenFlags) -> u32 {
    u32::from(flags.contains(OpenFlags::CREATE))
        | (u32::from(flags.contains(OpenFlags::DIRECTORY)) << 1)
        | (u32::from(flags.contains(OpenFlags::EXCLUSIVE)) << 2)
        | (u32::from(flags.contains(OpenFlags::TRUNCATE)) << 3)
}

fn descriptor_flags_bits(flags: DescriptorFlags) -> u32 {
    u32::from(flags.contains(DescriptorFlags::READ))
        | (u32::from(flags.contains(DescriptorFlags::WRITE)) << 1)
        | (u32::from(flags.contains(DescriptorFlags::FILE_INTEGRITY_SYNC)) << 2)
        | (u32::from(flags.contains(DescriptorFlags::DATA_INTEGRITY_SYNC)) << 3)
        | (u32::from(flags.contains(DescriptorFlags::REQUESTED_WRITE_SYNC)) << 4)
        | (u32::from(flags.contains(DescriptorFlags::MUTATE_DIRECTORY)) << 5)
}

fn expected_path_flags() -> PathFlags {
    PathFlags::SYMLINK_FOLLOW
}

fn expected_open_flags() -> OpenFlags {
    OpenFlags::CREATE
}

fn expected_descriptor_flags() -> DescriptorFlags {
    DescriptorFlags::READ | DescriptorFlags::WRITE
}

fn snapshot(stats: &Arc<Mutex<Stats>>) -> Stats {
    stats.lock().expect("open-at stats mutex poisoned").clone()
}

fn observed_path(stats: &Stats) -> &str {
    stats.observed_path.as_deref().unwrap_or("<none>")
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
            let descriptor = store
                .data_mut()
                .table
                .delete(Resource::<Descriptor>::new_own(rep))?;
            let mut stats = store
                .data()
                .stats
                .lock()
                .expect("open-at stats mutex poisoned");
            if descriptor.is_dir {
                stats.parent_drops += 1;
            } else {
                stats.child_drops += 1;
            }
            Ok(())
        },
    )?;

    let method_stats = Arc::clone(&stats);
    types.func_wrap_concurrent(
        "[method]descriptor.open-at",
        move |accessor,
              (descriptor, path_flags, path, open_flags, descriptor_flags): (
            Resource<Descriptor>,
            PathFlags,
            String,
            OpenFlags,
            DescriptorFlags,
        )| {
            let parent_path = match accessor.with(|mut access| {
                let descriptor = access.data_mut().table.get(&descriptor)?;
                if !descriptor.is_dir {
                    return Err(wasmtime::Error::msg("open-at receiver is not a directory"));
                }
                let parent_path = descriptor.path.clone();
                let mut stats = access
                    .data_mut()
                    .stats
                    .lock()
                    .expect("open-at stats mutex poisoned");
                stats.host_calls += 1;
                stats.path_copies += 1;
                Ok::<PathBuf, wasmtime::Error>(parent_path)
            }) {
                Ok(path) => path,
                Err(error) => return Box::pin(async move { Err(error) }),
            };
            let copied_path = path.clone();
            Box::pin(OpenFuture {
                accessor,
                stats: Arc::clone(&method_stats),
                parent_path,
                path: copied_path,
                path_flags,
                open_flags,
                descriptor_flags,
                output_error: mode == Mode::Error,
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
    run: RunFunc,
    descriptor: Resource<Descriptor>,
    path_flags: PathFlags,
    path: String,
    open_flags: OpenFlags,
    descriptor_flags: DescriptorFlags,
) -> Result<OpenResult> {
    let result = map_wasmtime(
        store
            .run_concurrent(async |accessor| {
                run.call_concurrent(
                    accessor,
                    (descriptor, path_flags, path, open_flags, descriptor_flags),
                )
                .await
            })
            .await,
    )?;
    Ok(map_wasmtime(result)?.0)
}

fn dispose_child(store: &mut Store<State>, child: Resource<Descriptor>) -> Result<()> {
    let descriptor = store.data_mut().table.delete(child)?;
    if descriptor.is_dir {
        bail!("open-at returned a directory resource instead of a child file");
    }
    store
        .data()
        .stats
        .lock()
        .expect("open-at stats mutex poisoned")
        .child_drops += 1;
    Ok(())
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
        .context("missing open-at probe export")?;
    let run_export = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing open-at probe.run export")?;
    let run = map_wasmtime(instance.get_typed_func::<(
        Resource<Descriptor>,
        PathFlags,
        String,
        OpenFlags,
        DescriptorFlags,
    ), (OpenResult,)>(&mut store, &run_export))?;

    let configured_path =
        std::env::var("DO_D2_FILESYSTEM_PATH").context("DO_D2_FILESYSTEM_PATH is required")?;
    if configured_path.is_empty() || Path::new(&configured_path).is_absolute() {
        bail!("DO_D2_FILESYSTEM_PATH must be a non-empty relative path");
    }
    let path = match mode {
        Mode::Pending => "é-file".to_owned(),
        Mode::Error => "missing-file".to_owned(),
        _ => configured_path,
    };
    let path_flags = expected_path_flags();
    let open_flags = expected_open_flags();
    let descriptor_flags = expected_descriptor_flags();
    let make_descriptor = |store: &mut Store<State>| {
        store.data_mut().table.push(Descriptor {
            path: root.clone(),
            is_dir: true,
        })
    };

    let mut repeat_results: Option<(OpenResult, OpenResult)> = None;
    let result = match mode {
        Mode::Cancel => {
            let cancel_export = instance
                .get_export_index(&mut store, Some(&probe), "cancel")
                .context("missing open-at probe.cancel export")?;
            let cancel =
                map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, &cancel_export))?;
            let descriptor = make_descriptor(&mut store)?;
            let run_handle = map_wasmtime(store.spawn(RunTask {
                run,
                descriptor,
                path_flags,
                path: path.clone(),
                open_flags,
                descriptor_flags,
            }))?;
            map_wasmtime(map_wasmtime(
                store
                    .run_concurrent(async |_accessor| {
                        futures::future::poll_fn(|cx| {
                            let snapshot = snapshot(&stats);
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
                run.call_concurrent(
                    accessor,
                    (
                        descriptor,
                        path_flags,
                        path.clone(),
                        open_flags,
                        descriptor_flags,
                    ),
                )
                .await
            });
            let started = futures::future::poll_fn(|cx| {
                let snapshot = snapshot(&stats);
                if snapshot.host_calls == 1 {
                    Poll::Ready(())
                } else {
                    cx.waker().wake_by_ref();
                    Poll::Pending
                }
            });
            let dropped = {
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
            if dropped {
                drop(store);
                let current = snapshot(&stats);
                if current.host_calls != 1
                    || current.completions != 0
                    || current.future_drops != 1
                    || current.pending_future_drops != 1
                    || current.parent_drops != 0
                    || current.child_drops != 0
                {
                    bail!(
                        "unexpected open-at early-drop cleanup: host-calls={} completions={} future-drops={} pending-future-drops={} parent-drops={} child-drops={}",
                        current.host_calls,
                        current.completions,
                        current.future_drops,
                        current.pending_future_drops,
                        current.parent_drops,
                        current.child_drops,
                    );
                }
                println!(
                    "mode=early-drop result=store-discarded host-calls={} path-copies={} observed-path={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} parent-drops={} child-drops={} table-empty=not-applicable",
                    current.host_calls,
                    current.path_copies,
                    observed_path(&current),
                    current.completion_polls,
                    current.external_wakes,
                    current.completions,
                    current.future_drops,
                    current.pending_future_drops,
                    current.parent_drops,
                    current.child_drops,
                );
                return Ok(());
            }
            unreachable!("early-drop select did not yield a drop path")
        }
        Mode::Repeat => {
            let first_descriptor = make_descriptor(&mut store)?;
            let first = call_run(
                &mut store,
                run,
                first_descriptor,
                path_flags,
                path.clone(),
                open_flags,
                descriptor_flags,
            )
            .await?;
            let second_descriptor = make_descriptor(&mut store)?;
            let second = call_run(
                &mut store,
                run,
                second_descriptor,
                path_flags,
                path.clone(),
                open_flags,
                descriptor_flags,
            )
            .await?;
            repeat_results = Some((first, second));
            None
        }
        Mode::Ready | Mode::Pending | Mode::Error => Some({
            let descriptor = make_descriptor(&mut store)?;
            call_run(
                &mut store,
                run,
                descriptor,
                path_flags,
                path,
                open_flags,
                descriptor_flags,
            )
            .await?
        }),
    };

    let current_result = match result {
        Some(Ok(child)) => {
            dispose_child(&mut store, child)?;
            Some(Ok(()))
        }
        Some(Err(error)) => Some(Err(error)),
        None => None,
    };
    let repeat_status = match repeat_results.take() {
        Some((first, second)) => {
            let first = match first {
                Ok(child) => {
                    dispose_child(&mut store, child)?;
                    Ok(())
                }
                Err(error) => Err(error),
            };
            let second = match second {
                Ok(child) => {
                    dispose_child(&mut store, child)?;
                    Ok(())
                }
                Err(error) => Err(error),
            };
            Some((first, second))
        }
        None => None,
    };

    let current = snapshot(&stats);
    if !store.data().table.is_empty() {
        bail!("unexpected open-at ResourceTable contents at terminal state");
    }
    match mode {
        Mode::Ready | Mode::Pending => {
            let value = current_result.context("missing open-at result")?;
            if !matches!(value, Ok(_)) {
                bail!("unexpected open-at success result: {value:?}");
            }
            println!(
                "mode={} result=Ok host-calls={} path-copies={} observed-path={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} parent-drops={} child-drops={} table-empty=true",
                mode.label(),
                current.host_calls,
                current.path_copies,
                observed_path(&current),
                current.completion_polls,
                current.external_wakes,
                current.completions,
                current.future_drops,
                current.pending_future_drops,
                current.parent_drops,
                current.child_drops,
            );
        }
        Mode::Error => {
            let value = current_result.context("missing open-at error result")?;
            if !matches!(value, Err(ErrorCode::NoEntry)) {
                bail!("unexpected open-at error result: {value:?}");
            }
            println!(
                "mode=error result=Err(no-entry) host-calls={} path-copies={} observed-path={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} parent-drops={} child-drops={} table-empty=true",
                current.host_calls,
                current.path_copies,
                observed_path(&current),
                current.completion_polls,
                current.external_wakes,
                current.completions,
                current.future_drops,
                current.pending_future_drops,
                current.parent_drops,
                current.child_drops,
            );
        }
        Mode::Cancel => {
            if current.completions != 0
                || current.pending_future_drops != 1
                || current.parent_drops != 1
                || current.child_drops != 0
            {
                bail!(
                    "unexpected open-at cancellation: completions={} pending-future-drops={} parent-drops={} child-drops={}",
                    current.completions,
                    current.pending_future_drops,
                    current.parent_drops,
                    current.child_drops,
                );
            }
            println!(
                "mode=cancel result=cancelled host-calls={} path-copies={} observed-path={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} parent-drops={} child-drops={} table-empty=true",
                current.host_calls,
                current.path_copies,
                observed_path(&current),
                current.completion_polls,
                current.external_wakes,
                current.completions,
                current.future_drops,
                current.pending_future_drops,
                current.parent_drops,
                current.child_drops,
            );
        }
        Mode::Repeat => {
            let (first, second) = repeat_status.context("missing repeat results")?;
            if !matches!(first, Ok(_)) || !matches!(second, Ok(_)) {
                bail!("unexpected open-at repeat result: {first:?}, {second:?}");
            }
            println!(
                "mode=repeat results=Ok,Ok host-calls={} path-copies={} observed-path={} completion-polls={} external-wakes={} completions={} future-drops={} pending-future-drops={} parent-drops={} child-drops={} table-empty=true",
                current.host_calls,
                current.path_copies,
                observed_path(&current),
                current.completion_polls,
                current.external_wakes,
                current.completions,
                current.future_drops,
                current.pending_future_drops,
                current.parent_drops,
                current.child_drops,
            );
        }
        Mode::EarlyDrop => unreachable!("early-drop returns after Store disposal"),
    }

    let expected_calls = if mode == Mode::Repeat { 2 } else { 1 };
    let expected_children = match mode {
        Mode::Ready | Mode::Pending | Mode::Repeat => expected_calls,
        Mode::Error | Mode::Cancel => 0,
        Mode::EarlyDrop => unreachable!(),
    };
    if current.host_calls != expected_calls
        || current.path_copies != expected_calls
        || current.parent_drops != expected_calls
        || current.child_created != expected_children
        || current.child_drops != expected_children
    {
        bail!(
            "unexpected open-at ownership counts: host-calls={} path-copies={} parent-drops={} child-created={} child-drops={} expected-calls={} expected-children={}",
            current.host_calls,
            current.path_copies,
            current.parent_drops,
            current.child_created,
            current.child_drops,
            expected_calls,
            expected_children,
        );
    }
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: wasi-filesystem-open-at <component.wasm> <mode>")?;
    let mode = args
        .next()
        .context("usage: wasi-filesystem-open-at <component.wasm> <mode>")?;
    if args.next().is_some() {
        bail!("usage: wasi-filesystem-open-at <component.wasm> <mode>");
    }
    futures::executor::block_on(run(Path::new(&component_path), Mode::parse(&mode)?))
}
