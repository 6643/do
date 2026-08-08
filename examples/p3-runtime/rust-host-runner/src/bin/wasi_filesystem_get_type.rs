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

#[derive(Default, Clone, Copy)]
struct Stats {
    host_calls: u32,
    completion_polls: u32,
    external_wakes: u32,
    future_drops: u32,
    pending_future_drops: u32,
    descriptor_drops: u32,
}

struct State {
    table: ResourceTable,
    stats: Arc<Mutex<Stats>>,
}

struct RunTask {
    run: TypedFunc<(Resource<Descriptor>,), (std::result::Result<DescriptorType, ErrorCode>,)>,
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
    ReadyDirectory,
    ReadyRegular,
    Pending,
    Error,
    Cancel,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "ready-directory" => Ok(Self::ReadyDirectory),
            "ready-regular" => Ok(Self::ReadyRegular),
            "pending" => Ok(Self::Pending),
            "error" => Ok(Self::Error),
            "cancel" => Ok(Self::Cancel),
            other => bail!(
                "mode must be ready-directory, ready-regular, pending, error, or cancel (got {other})"
            ),
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::ReadyDirectory => "ready-directory",
            Self::ReadyRegular => "ready-regular",
            Self::Pending => "pending",
            Self::Error => "error",
            Self::Cancel => "cancel",
        }
    }

    fn path(self, root: &Path) -> PathBuf {
        match self {
            Self::ReadyDirectory | Self::Pending | Self::Cancel => root.join("dir"),
            Self::ReadyRegular => root.join("file"),
            Self::Error => root.join("missing"),
        }
    }
}

struct GetTypeFuture {
    stats: Arc<Mutex<Stats>>,
    output: std::result::Result<DescriptorType, ErrorCode>,
    pending_once: bool,
    never_ready: bool,
    was_pending: bool,
    completed: bool,
}

impl Future for GetTypeFuture {
    type Output = wasmtime::Result<(std::result::Result<DescriptorType, ErrorCode>,)>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        self.stats
            .lock()
            .expect("get-type stats mutex poisoned")
            .completion_polls += 1;
        if self.never_ready {
            self.was_pending = true;
            return Poll::Pending;
        }
        if self.pending_once && !self.was_pending {
            self.was_pending = true;
            self.stats
                .lock()
                .expect("get-type stats mutex poisoned")
                .external_wakes += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        self.completed = true;
        Poll::Ready(Ok((self.output,)))
    }
}

impl Drop for GetTypeFuture {
    fn drop(&mut self) {
        let mut stats = self.stats.lock().expect("get-type stats mutex poisoned");
        stats.future_drops += 1;
        if !self.completed {
            stats.pending_future_drops += 1;
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn classify(path: &Path) -> std::result::Result<DescriptorType, ErrorCode> {
    let metadata = match std::fs::metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Err(ErrorCode::NoEntry);
        }
        Err(_) => return Err(ErrorCode::Io),
    };
    if metadata.is_dir() {
        Ok(DescriptorType::Directory)
    } else if metadata.is_file() {
        Ok(DescriptorType::RegularFile)
    } else {
        Ok(DescriptorType::Unknown)
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
        "[method]descriptor.get-type",
        move |accessor, (descriptor,): (Resource<Descriptor>,)| {
            let path = match accessor.with(|mut store| {
                let path = store.data_mut().table.get(&descriptor)?.path.clone();
                store
                    .data_mut()
                    .stats
                    .lock()
                    .expect("get-type stats mutex poisoned")
                    .host_calls += 1;
                Ok::<PathBuf, wasmtime::Error>(path)
            }) {
                Ok(path) => path,
                Err(error) => return Box::pin(async move { Err(error) }),
            };
            let output = if mode == Mode::Error {
                Err(ErrorCode::NoEntry)
            } else {
                classify(&path)
            };
            Box::pin(GetTypeFuture {
                stats: Arc::clone(&method_stats),
                output,
                pending_once: mode == Mode::Pending,
                never_ready: mode == Mode::Cancel,
                was_pending: false,
                completed: false,
            })
        },
    )?;
    Ok(())
}

async fn call_run(
    store: &mut Store<State>,
    run: wasmtime::component::TypedFunc<
        (Resource<Descriptor>,),
        (std::result::Result<DescriptorType, ErrorCode>,),
    >,
    descriptor: Resource<Descriptor>,
) -> Result<(std::result::Result<DescriptorType, ErrorCode>,)> {
    let result = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(accessor, (descriptor,)).await)
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
    let descriptor_path = mode.path(&root);
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
    let descriptor = store.data_mut().table.push(Descriptor {
        path: descriptor_path,
    })?;
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_INSTANCE)
        .context("missing filesystem probe export")?;
    let run_export = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing filesystem probe.run export")?;
    let run = map_wasmtime(instance.get_typed_func::<
        (Resource<Descriptor>,),
        (std::result::Result<DescriptorType, ErrorCode>,),
    >(&mut store, &run_export))?;

    let result = if mode == Mode::Cancel {
        let cancel_export = instance
            .get_export_index(&mut store, Some(&probe), "cancel")
            .context("missing filesystem probe.cancel export")?;
        let cancel = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, &cancel_export))?;
        let run_handle = map_wasmtime(store.spawn(RunTask { run, descriptor }))?;
        map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |_accessor| {
                    futures::future::poll_fn(|cx| {
                        let snapshot = *stats.lock().expect("get-type stats mutex poisoned");
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
    } else {
        Some(call_run(&mut store, run, descriptor).await?)
    };

    let snapshot = *stats.lock().expect("get-type stats mutex poisoned");
    let table_empty = store.data().table.is_empty();
    if !table_empty || snapshot.host_calls != 1 || snapshot.descriptor_drops != 1 {
        bail!(
            "unexpected get-type cleanup: host-calls={} descriptor-drops={} table-empty={table_empty}",
            snapshot.host_calls,
            snapshot.descriptor_drops,
        );
    }
    if mode == Mode::Cancel {
        if snapshot.pending_future_drops != 1 || result.is_some() {
            bail!(
                "unexpected cancel stats: pending-future-drops={} result-present={}",
                snapshot.pending_future_drops,
                result.is_some(),
            );
        }
        println!(
            "mode={} result=cancelled host-calls={} completion-polls={} external-wakes={} future-drops={} pending-future-drops={} descriptor-drops={} table-empty=true",
            mode.label(),
            snapshot.host_calls,
            snapshot.completion_polls,
            snapshot.external_wakes,
            snapshot.future_drops,
            snapshot.pending_future_drops,
            snapshot.descriptor_drops,
        );
        return Ok(());
    }

    let (value,) = result.context("missing get-type result")?;
    let result_label = match value {
        Ok(DescriptorType::Directory) => "Ok(directory)",
        Ok(DescriptorType::RegularFile) => "Ok(regular-file)",
        Ok(_) => "Ok(other)",
        Err(ErrorCode::NoEntry) => "Err(no-entry)",
        Err(_) => "Err(other)",
    };
    let expected = match mode {
        Mode::ReadyDirectory | Mode::Pending => "Ok(directory)",
        Mode::ReadyRegular => "Ok(regular-file)",
        Mode::Error => "Err(no-entry)",
        Mode::Cancel => unreachable!(),
    };
    if result_label != expected {
        bail!("unexpected get-type result: expected {expected}, got {result_label}");
    }
    println!(
        "mode={} result={} host-calls={} completion-polls={} external-wakes={} future-drops={} pending-future-drops={} descriptor-drops={} table-empty=true",
        mode.label(),
        result_label,
        snapshot.host_calls,
        snapshot.completion_polls,
        snapshot.external_wakes,
        snapshot.future_drops,
        snapshot.pending_future_drops,
        snapshot.descriptor_drops,
    );
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: do-p3-wasi-filesystem-get-type-host-runner <component.wasm> <mode>")?;
    let mode = args
        .next()
        .context("usage: do-p3-wasi-filesystem-get-type-host-runner <component.wasm> <mode>")?;
    if args.next().is_some() {
        bail!("usage: do-p3-wasi-filesystem-get-type-host-runner <component.wasm> <mode>");
    }
    futures::executor::block_on(run(Path::new(&component_path), Mode::parse(&mode)?))
}
