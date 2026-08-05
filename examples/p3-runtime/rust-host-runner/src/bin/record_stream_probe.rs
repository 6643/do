use anyhow::{Context, Result, bail};
use std::collections::VecDeque;
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Destination, FutureReader, Linker, ResourceTable, StreamProducer, StreamReader,
    StreamResult, VecBuffer,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const SOURCE_INSTANCE: &str = "do:record-stream-probe/source@0.1.0";
const PROBE_INSTANCE: &str = "do:record-stream-probe/probe@0.1.0";

#[derive(
    Clone,
    Debug,
    PartialEq,
    wasmtime::component::ComponentType,
    wasmtime::component::Lift,
    wasmtime::component::Lower,
)]
#[component(record)]
struct ProbeEntry {
    id: u32,
    label: String,
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
    #[component(name = "io")]
    Io,
    #[component(name = "no-entry")]
    NoEntry,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CompletionMode {
    Pending,
    Ready,
    Error,
}

#[derive(Default)]
struct Stats {
    entries: Vec<(u32, String)>,
    stream_read_calls: u32,
    completion_polls: u32,
    pending_wakes: u32,
    stream_drops: u32,
    future_drops: u32,
    eof: bool,
}

struct State {
    table: ResourceTable,
}

struct ProbeStream {
    stats: Arc<Mutex<Stats>>,
    entries: VecDeque<ProbeEntry>,
    eof: bool,
}

impl StreamProducer<State> for ProbeStream {
    type Item = ProbeEntry;
    type Buffer = VecBuffer<ProbeEntry>;

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
            .expect("record stream stats mutex poisoned")
            .stream_read_calls += 1;
        let Some(entry) = stream.entries.pop_front() else {
            stream.eof = true;
            stream
                .stats
                .lock()
                .expect("record stream stats mutex poisoned")
                .eof = true;
            destination.set_buffer(Vec::new().into());
            return Poll::Ready(Ok(StreamResult::Dropped));
        };
        stream
            .stats
            .lock()
            .expect("record stream stats mutex poisoned")
            .entries
            .push((entry.id, entry.label.clone()));
        destination.set_buffer(vec![entry].into());
        Poll::Ready(Ok(StreamResult::Completed))
    }
}

impl Drop for ProbeStream {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("record stream stats mutex poisoned")
            .stream_drops += 1;
    }
}

struct ProbeCompletion {
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
    polled: bool,
}

impl Future for ProbeCompletion {
    type Output = wasmtime::Result<std::result::Result<(), ErrorCode>>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        self.stats
            .lock()
            .expect("record completion stats mutex poisoned")
            .completion_polls += 1;
        if self.mode == CompletionMode::Pending && !self.polled {
            self.polled = true;
            self.stats
                .lock()
                .expect("record completion stats mutex poisoned")
                .pending_wakes += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }
        self.polled = true;
        if self.mode == CompletionMode::Error {
            Poll::Ready(Ok(Err(ErrorCode::Io)))
        } else {
            Poll::Ready(Ok(Ok(())))
        }
    }
}

impl Drop for ProbeCompletion {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("record completion stats mutex poisoned")
            .future_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn install_source(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: CompletionMode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_INSTANCE)?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let stats = Arc::clone(&stats);
        let reader = StreamReader::new(
            &mut store,
            ProbeStream {
                stats: Arc::clone(&stats),
                entries: VecDeque::from([
                    ProbeEntry {
                        id: 1,
                        label: "alpha".to_owned(),
                    },
                    ProbeEntry {
                        id: 2,
                        label: "beta".to_owned(),
                    },
                ]),
                eof: false,
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            ProbeCompletion {
                stats: Arc::clone(&stats),
                mode,
                polled: false,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

async fn run(component_path: &Path, mode: CompletionMode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker = Linker::new(&engine);
    map_wasmtime(install_source(&mut linker, Arc::clone(&stats), mode))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let probe = instance
        .get_export_index(&mut store, None, PROBE_INSTANCE)
        .context("missing record-stream probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing record-stream probe.run export")?;
    let run = map_wasmtime(
        instance.get_typed_func::<(), (std::result::Result<(), ErrorCode>,)>(&mut store, &run),
    )?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    let result = map_wasmtime(call)?;
    let expected_result = if mode == CompletionMode::Error {
        Err(ErrorCode::Io)
    } else {
        Ok(())
    };
    if result.0 != expected_result {
        bail!("unexpected result: {:?}", result.0);
    }
    let snapshot = stats.lock().expect("record stats mutex poisoned");
    let expected_entries = vec![(1, "alpha".to_owned()), (2, "beta".to_owned())];
    let expected_polls = if mode == CompletionMode::Pending {
        2
    } else {
        1
    };
    if snapshot.entries != expected_entries
        || snapshot.stream_read_calls != 3
        || !snapshot.eof
        || snapshot.completion_polls != expected_polls
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || snapshot.pending_wakes
            != if mode == CompletionMode::Pending {
                1
            } else {
                0
            }
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected record stream stats: entries={:?} reads={} eof={} completion-polls={} stream-drops={} future-drops={} external-wakes={}",
            snapshot.entries,
            snapshot.stream_read_calls,
            snapshot.eof,
            snapshot.completion_polls,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.pending_wakes,
        );
    }
    println!(
        "Rust generic record stream {} passed entries=[(1,alpha),(2,beta)] eof=true stream-reads=3 completion-polls={} pending-wakes={} stream-drops=1 future-drops=1 table-empty=true result={}",
        match mode {
            CompletionMode::Pending => "pending",
            CompletionMode::Ready => "ready",
            CompletionMode::Error => "error",
        },
        snapshot.completion_polls,
        snapshot.pending_wakes,
        if mode == CompletionMode::Error {
            "Err(io)"
        } else {
            "Ok"
        },
    );
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-record-stream-host-runner <component.wasm>")?;
    let mode = match std::env::var("DO_RECORD_STREAM_COMPLETION").as_deref() {
        Ok("ready") => CompletionMode::Ready,
        Ok("error") => CompletionMode::Error,
        Ok("pending") | Err(_) => CompletionMode::Pending,
        Ok(other) => {
            bail!("DO_RECORD_STREAM_COMPLETION must be pending, ready, or error (got {other})")
        }
    };
    futures::executor::block_on(run(Path::new(&component_path), mode))
}
