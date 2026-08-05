use anyhow::{Context, Result, bail};
use std::collections::VecDeque;
use std::fs;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Destination, FutureReader, Linker, Resource, ResourceTable, ResourceType,
    StreamProducer, StreamReader, StreamResult, VecBuffer,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const TYPES_INSTANCE: &str = "wasi:filesystem/types@0.3.0-rc-2025-09-16";
const PROBE_INSTANCE: &str = "wasi:filesystem/probe@0.3.0-rc-2025-09-16";

pub struct Descriptor {
    root: Option<PathBuf>,
}

#[derive(
    Clone,
    Copy,
    Debug,
    PartialEq,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(enum)]
#[repr(u8)]
#[allow(dead_code)]
enum DescriptorType {
    #[component(name = "unknown")]
    Unknown,
    #[component(name = "directory")]
    Directory,
    #[component(name = "regular-file")]
    RegularFile,
}

#[derive(
    Clone,
    Debug,
    PartialEq,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(record)]
struct DirectoryEntry {
    #[component(name = "type")]
    ty: DescriptorType,
    name: String,
}

#[derive(
    Clone,
    Copy,
    Debug,
    PartialEq,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(enum)]
#[repr(u8)]
#[allow(dead_code)]
enum ErrorCode {
    #[component(name = "access")]
    Access,
    #[component(name = "io")]
    Io,
    #[component(name = "no-entry")]
    NoEntry,
}

#[derive(Default)]
struct Stats {
    read_directory_calls: u32,
    stream_read_calls: u32,
    entries_produced: u32,
    entry_names: Vec<String>,
    completion_polls: u32,
    descriptor_drops: u32,
    stream_drops: u32,
    future_drops: u32,
}

struct State {
    table: ResourceTable,
    stats: Arc<Mutex<Stats>>,
}

struct DirectoryStream {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<DirectoryEntry>,
    eof_observed: bool,
}

fn read_real_directory(root: &Path) -> wasmtime::Result<VecDeque<DirectoryEntry>> {
    let mut entries = fs::read_dir(root)
        .map_err(|error| {
            wasmtime::Error::msg(format!("read directory {}: {error}", root.display()))
        })?
        .map(|entry| {
            let entry = entry
                .map_err(|error| wasmtime::Error::msg(format!("read directory entry: {error}")))?;
            let file_type = entry.file_type().map_err(|error| {
                wasmtime::Error::msg(format!("read directory entry type: {error}"))
            })?;
            let name = entry
                .file_name()
                .into_string()
                .map_err(|_| wasmtime::Error::msg("directory entry name is not valid UTF-8"))?;
            let ty = if file_type.is_dir() {
                DescriptorType::Directory
            } else if file_type.is_file() {
                DescriptorType::RegularFile
            } else {
                DescriptorType::Unknown
            };
            Ok((name, ty))
        })
        .collect::<wasmtime::Result<Vec<(String, DescriptorType)>>>()?;
    entries.sort_by(|left, right| left.0.cmp(&right.0));
    Ok(entries
        .into_iter()
        .map(|(name, ty)| DirectoryEntry { ty, name })
        .collect())
}

impl DirectoryStream {
    fn take_next(&mut self) -> std::result::Result<Option<DirectoryEntry>, &'static str> {
        if self.eof_observed {
            return Err("stream read after EOF");
        }
        if let Some(entry) = self.entries.pop_front() {
            return Ok(Some(entry));
        }
        self.eof_observed = true;
        Ok(None)
    }
}

impl StreamProducer<State> for DirectoryStream {
    type Item = DirectoryEntry;
    type Buffer = VecBuffer<DirectoryEntry>;

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
        let stream = self.get_mut();
        stream
            .stats
            .lock()
            .expect("directory stream stats mutex poisoned")
            .stream_read_calls += 1;
        let entry = stream.take_next().map_err(wasmtime::Error::msg)?;
        if let Some(entry) = entry {
            let entry_name = entry.name.clone();
            destination.set_buffer(vec![entry].into());
            let mut stats = stream
                .stats
                .lock()
                .expect("directory stream stats mutex poisoned");
            stats.entries_produced += 1;
            stats.entry_names.push(entry_name);
        } else {
            destination.set_buffer(Vec::new().into());
        }
        Poll::Ready(Ok(if stream.eof_observed {
            StreamResult::Dropped
        } else {
            StreamResult::Completed
        }))
    }
}

impl Drop for DirectoryStream {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("directory stream stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct Completion {
    stats: Arc<Mutex<Stats>>,
    pending_once: bool,
    polled: bool,
}

impl Future for Completion {
    type Output = wasmtime::Result<std::result::Result<(), ErrorCode>>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        let pending = self.pending_once && !self.polled;
        self.polled = true;
        self.stats
            .lock()
            .expect("directory completion stats mutex poisoned")
            .completion_polls += 1;
        if pending {
            cx.waker().wake_by_ref();
            Poll::Pending
        } else {
            Poll::Ready(Ok(Ok(())))
        }
    }
}

impl Drop for Completion {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("directory completion stats mutex poisoned")
            .future_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn install_types(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    completion_pending_once: bool,
    bounded: bool,
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
        "[method]descriptor.read-directory",
        move |accessor, (descriptor,): (Resource<Descriptor>,)| {
            let method_stats = Arc::clone(&method_stats);
            Box::pin(async move {
                accessor.with(|mut store| {
                    let descriptor_root = store.data_mut().table.get(&descriptor)?.root.clone();
                    method_stats
                        .lock()
                        .expect("read-directory stats mutex poisoned")
                        .read_directory_calls += 1;
                    let entries = if let Some(root) = descriptor_root {
                        read_real_directory(&root)?
                    } else if bounded {
                        VecDeque::from([
                            DirectoryEntry {
                                ty: DescriptorType::RegularFile,
                                name: "alpha".to_owned(),
                            },
                            DirectoryEntry {
                                ty: DescriptorType::Directory,
                                name: "beta".to_owned(),
                            },
                        ])
                    } else {
                        VecDeque::from([DirectoryEntry {
                            ty: DescriptorType::RegularFile,
                            name: "alpha".to_owned(),
                        }])
                    };
                    let reader = StreamReader::new(
                        &mut store,
                        DirectoryStream {
                            stats: Arc::clone(&method_stats),
                            entries,
                            eof_observed: false,
                        },
                    )?;
                    let completion = FutureReader::new(
                        &mut store,
                        Completion {
                            stats: Arc::clone(&method_stats),
                            pending_once: completion_pending_once,
                            polled: false,
                        },
                    )?;
                    Ok(((reader, completion),))
                })
            })
        },
    )?;
    Ok(())
}

async fn run(component_path: &Path, completion_pending_once: bool) -> Result<()> {
    let bounded = std::env::var_os("DO_READ_DIRECTORY_BOUNDED").is_some();
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
    map_wasmtime(install_types(
        &mut linker,
        Arc::clone(&stats),
        completion_pending_once,
        bounded,
    ))?;

    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Arc::clone(&stats),
        },
    );
    let root = std::env::var_os("DO_D2_FILESYSTEM_ROOT").map(PathBuf::from);
    let descriptor = store.data_mut().table.push(Descriptor { root })?;
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_INSTANCE)
        .context("missing filesystem probe export")?;
    let export_name = if bounded { "run-bounded" } else { "run" };
    let run = instance
        .get_export_index(&mut store, Some(&probe), export_name)
        .with_context(|| format!("missing filesystem probe.{export_name} export"))?;
    let run =
        map_wasmtime(instance.get_typed_func::<(Resource<Descriptor>,), ()>(&mut store, &run))?;
    let call = match map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(accessor, (descriptor,)).await)
            .await,
    ) {
        Ok(call) => call,
        Err(error) => {
            let snapshot = stats.lock().expect("directory stats mutex poisoned");
            eprintln!(
                "read-directory trap stats: calls={} entries={} completion-polls={} descriptor-drops={} stream-drops={} future-drops={}",
                snapshot.read_directory_calls,
                snapshot.entries_produced,
                snapshot.completion_polls,
                snapshot.descriptor_drops,
                snapshot.stream_drops,
                snapshot.future_drops
            );
            return Err(error);
        }
    };
    map_wasmtime(call)?;

    let snapshot = stats.lock().expect("directory stats mutex poisoned");
    let expected_entries = if bounded { 2 } else { 1 };
    let expected_reads = if bounded { 3 } else { 1 };
    if snapshot.read_directory_calls != 1
        || snapshot.stream_read_calls != expected_reads
        || snapshot.entries_produced != expected_entries
        || snapshot.completion_polls != if completion_pending_once { 2 } else { 1 }
        || snapshot.descriptor_drops != 1
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected read-directory stats: calls={} reads={} entries={} completion-polls={} descriptor-drops={} stream-drops={} future-drops={} table-empty={}",
            snapshot.read_directory_calls,
            snapshot.stream_read_calls,
            snapshot.entries_produced,
            snapshot.completion_polls,
            snapshot.descriptor_drops,
            snapshot.stream_drops,
            snapshot.future_drops,
            store.data().table.is_empty(),
        );
    }

    println!("Rust WASI read-directory adapter passed");
    if bounded {
        println!("entry-names={}", snapshot.entry_names.join(","));
    } else {
        println!("entry-name=alpha");
    }
    println!("stream-reads={}", snapshot.stream_read_calls);
    println!(
        "completion-mode={}",
        if completion_pending_once {
            "pending-once"
        } else {
            "ready"
        }
    );
    println!("descriptor-drops=1 stream-drops=1 future-drops=1 table-empty=true");
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-wasi-filesystem-read-directory-host-runner <component.wasm>")?;
    let completion_pending_once = std::env::var_os("DO_READ_DIRECTORY_COMPLETION_READY").is_none();
    futures::executor::block_on(run(Path::new(&component_path), completion_pending_once))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn real_directory_entries_are_sorted_and_typed() {
        let root = std::env::temp_dir().join(format!("do-real-directory-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("bravo")).expect("create real directory fixture");
        fs::write(root.join("alpha"), b"alpha").expect("create real file fixture");

        let entries = read_real_directory(&root).expect("read real directory fixture");
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].name, "alpha");
        assert_eq!(entries[0].ty, DescriptorType::RegularFile);
        assert_eq!(entries[1].name, "bravo");
        assert_eq!(entries[1].ty, DescriptorType::Directory);

        fs::remove_dir_all(root).expect("remove real directory fixture");
    }

    #[test]
    fn bounded_directory_sequence_ends_once_and_rejects_a_fourth_read() {
        let stats = Arc::new(Mutex::new(Stats::default()));
        let mut stream = DirectoryStream {
            stats,
            entries: VecDeque::from([
                DirectoryEntry {
                    ty: DescriptorType::RegularFile,
                    name: "alpha".to_owned(),
                },
                DirectoryEntry {
                    ty: DescriptorType::Directory,
                    name: "beta".to_owned(),
                },
            ]),
            eof_observed: false,
        };
        try_entry_name(&mut stream, "alpha");
        try_entry_name(&mut stream, "beta");
        assert!(stream.take_next().expect("EOF probe").is_none());
        assert_eq!(stream.take_next(), Err("stream read after EOF"));
    }

    fn try_entry_name(stream: &mut DirectoryStream, expected: &str) {
        let entry = stream
            .take_next()
            .expect("entry read")
            .expect("expected entry");
        assert_eq!(entry.name, expected);
    }
}
