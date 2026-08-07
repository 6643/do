use anyhow::{Context, Result, bail};
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Linker, Resource, ResourceTable, ResourceType, Source, StreamConsumer, StreamReader,
    StreamResult,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const TYPES_INSTANCE: &str = "do:g6-2-batched-list-producer/types@0.1.0";
const SOURCE_INSTANCE: &str = "do:g6-2-batched-list-producer/source@0.1.0";
const SINK_INSTANCE: &str = "do:g6-2-batched-list-producer/sink@0.1.0";

const LIST_POINTER: u32 = 64;
const LIST_LENGTH: u32 = 68;
const LIST_POINTER_BATCH1: u32 = 72;
const LIST_LENGTH_BATCH1: u32 = 76;
const LIST_ELEMENT_STRIDE: u32 = 4;
const LIST_TICKET_OFFSET: u32 = 0;
const STREAM_CAPACITY: u32 = 1;

pub struct Ticket {
    seed: u32,
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
#[component(enum)]
#[repr(u8)]
#[allow(dead_code)]
enum ErrorCode {
    #[component(name = "io")]
    Io,
    #[component(name = "pipe")]
    Pipe,
    #[component(name = "invalid-mode")]
    InvalidMode,
}

#[derive(
    wasmtime::component::ComponentType, wasmtime::component::Lift, wasmtime::component::Lower,
)]
#[component(record)]
struct ResourceEntry {
    ticket: Resource<Ticket>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Ready,
    Pending,
    SinkErrorFirst,
    SinkErrorSecond,
    CancelBeforeFirst,
    CancelAfterFirst,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "ready" => Ok(Self::Ready),
            "pending" => Ok(Self::Pending),
            "sink-error-first" => Ok(Self::SinkErrorFirst),
            "sink-error-second" => Ok(Self::SinkErrorSecond),
            "cancel-before-first" => Ok(Self::CancelBeforeFirst),
            "cancel-after-first" => Ok(Self::CancelAfterFirst),
            other => bail!(
                "mode must be ready, pending, sink-error-first, sink-error-second, cancel-before-first, or cancel-after-first (got {other})"
            ),
        }
    }

    fn input(self) -> u32 {
        match self {
            Self::Ready => 0,
            Self::Pending => 1,
            Self::SinkErrorFirst => 2,
            Self::SinkErrorSecond => 3,
            Self::CancelBeforeFirst => 4,
            Self::CancelAfterFirst => 5,
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Ready => "ready",
            Self::Pending => "pending",
            Self::SinkErrorFirst => "sink-error-first",
            Self::SinkErrorSecond => "sink-error-second",
            Self::CancelBeforeFirst => "cancel-before-first",
            Self::CancelAfterFirst => "cancel-after-first",
        }
    }

    fn expected_batches(self) -> &'static [&'static [u32]] {
        match self {
            Self::Ready | Self::Pending | Self::SinkErrorSecond => &[&[111, 222], &[333]],
            Self::SinkErrorFirst => &[&[111, 222]],
            Self::CancelBeforeFirst => &[],
            Self::CancelAfterFirst => &[&[111, 222]],
        }
    }

    fn sink_pending(self) -> bool {
        matches!(self, Self::Pending)
    }

    fn sink_error_after(self) -> Option<usize> {
        match self {
            Self::SinkErrorFirst => Some(1),
            Self::SinkErrorSecond => Some(2),
            _ => None,
        }
    }

    fn hold_call(self) -> bool {
        matches!(self, Self::CancelBeforeFirst | Self::CancelAfterFirst)
    }
}

#[derive(Default)]
struct Stats {
    created: u32,
    resource_drops: u32,
    received: Vec<Vec<u32>>,
    host_calls: u32,
    pending_polls: u32,
    stream_drops: u32,
    future_drops: u32,
    cancel_calls: u32,
}

struct State {
    table: ResourceTable,
}

struct Sink {
    stats: Arc<Mutex<Stats>>,
    pending_once: bool,
    drop_after_batch: Option<usize>,
    transfer_sender: Option<futures::channel::oneshot::Sender<()>>,
}

impl StreamConsumer<State> for Sink {
    type Item = Vec<ResourceEntry>;

    fn poll_consume(
        mut self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'_, State>,
        mut source: Source<'_, Self::Item>,
        finish: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        if finish {
            self.stats
                .lock()
                .expect("batched sink stats mutex poisoned")
                .cancel_calls += 1;
            return Poll::Ready(Ok(StreamResult::Cancelled));
        }

        if self.pending_once {
            self.pending_once = false;
            self.stats
                .lock()
                .expect("batched sink stats mutex poisoned")
                .pending_polls += 1;
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }

        let remaining = source.remaining(&mut store);
        if remaining == 0 {
            return Poll::Pending;
        }
        let mut items = Vec::with_capacity(remaining);
        source.read(&mut store, &mut items).map_err(|error| {
            wasmtime::Error::msg(format!("batched source list lift failed: {error:#}"))
        })?;
        for entries in items {
            let mut batch = Vec::with_capacity(entries.len());
            for entry in entries {
                let ticket = Resource::<Ticket>::new_own(entry.ticket.rep());
                let seed = store.data().table.get(&ticket)?.seed;
                store.data_mut().table.delete(ticket)?;
                batch.push(seed);
                self.stats
                    .lock()
                    .expect("batched resource stats mutex poisoned")
                    .resource_drops += 1;
            }
            let mut stats = self
                .stats
                .lock()
                .expect("batched batch stats mutex poisoned");
            stats.received.push(batch);
        }
        if let Some(sender) = self.transfer_sender.take() {
            let _ = sender.send(());
        }
        let stop = self.drop_after_batch.is_some_and(|limit| {
            self.stats
                .lock()
                .expect("batched stop stats mutex poisoned")
                .received
                .len()
                >= limit
        });
        if stop {
            Poll::Ready(Ok(StreamResult::Dropped))
        } else {
            Poll::Ready(Ok(StreamResult::Completed))
        }
    }
}

impl Drop for Sink {
    fn drop(&mut self) {
        let mut stats = self
            .stats
            .lock()
            .expect("batched sink drop stats mutex poisoned");
        stats.stream_drops += 1;
        stats.future_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn install_types(linker: &mut Linker<State>, stats: Arc<Mutex<Stats>>) -> wasmtime::Result<()> {
    let mut types = linker.instance(TYPES_INSTANCE)?;
    types.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        move |mut store, rep| {
            store
                .data_mut()
                .table
                .delete(Resource::<Ticket>::new_own(rep))?;
            stats
                .lock()
                .expect("batched guest drop stats mutex poisoned")
                .resource_drops += 1;
            Ok(())
        },
    )?;
    Ok(())
}

fn install_source(linker: &mut Linker<State>, stats: Arc<Mutex<Stats>>) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_INSTANCE)?;
    source.func_wrap("make-ticket", move |mut store, (seed,): (u32,)| {
        let ticket = store.data_mut().table.push(Ticket { seed })?;
        stats
            .lock()
            .expect("batched source stats mutex poisoned")
            .created += 1;
        Ok((ticket,))
    })?;
    Ok(())
}

fn install_sink(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: Mode,
    transfer_sender: futures::channel::oneshot::Sender<()>,
) -> wasmtime::Result<()> {
    let mut sink = linker.instance(SINK_INSTANCE)?;
    let host_stats = Arc::clone(&stats);
    let transfer_sender = Arc::new(Mutex::new(Some(transfer_sender)));
    sink.func_wrap_concurrent(
        "consume-via-stream",
        move |accessor, (reader,): (StreamReader<Vec<ResourceEntry>>,)| {
            host_stats
                .lock()
                .expect("batched host call stats mutex poisoned")
                .host_calls += 1;
            let stats = Arc::clone(&host_stats);
            let transfer_sender = transfer_sender
                .lock()
                .expect("batched transfer sender mutex poisoned")
                .take();
            let future = async move {
                accessor.with(|mut store| {
                    reader.pipe(
                        &mut store,
                        Sink {
                            stats: Arc::clone(&stats),
                            pending_once: mode.sink_pending(),
                            drop_after_batch: mode.sink_error_after(),
                            transfer_sender,
                        },
                    )
                })?;
                if mode.hold_call() {
                    futures::future::pending::<()>().await;
                }
                let result = if mode.sink_error_after().is_some() {
                    Err(ErrorCode::Pipe)
                } else {
                    Ok(())
                };
                Ok::<(std::result::Result<(), ErrorCode>,), wasmtime::Error>((result,))
            };
            Box::pin(future)
        },
    )?;
    Ok(())
}

async fn run(component_path: &Path, mode: Mode) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    config.wasm_component_model_async(true);
    config.wasm_component_model_more_async_builtins(true);
    config.concurrency_support(true);

    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))
        .with_context(|| format!("load component {}", component_path.display()))?;
    let stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker: Linker<State> = Linker::new(&engine);
    map_wasmtime(install_types(&mut linker, Arc::clone(&stats)))?;
    map_wasmtime(install_source(&mut linker, Arc::clone(&stats)))?;
    let (transfer_sender, _transfer_receiver) = futures::channel::oneshot::channel();
    map_wasmtime(install_sink(
        &mut linker,
        Arc::clone(&stats),
        mode,
        transfer_sender,
    ))?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let produce = map_wasmtime(
        instance
            .get_typed_func::<(u32,), (std::result::Result<(), ErrorCode>,)>(&mut store, "produce"),
    )?;
    let result = map_wasmtime(map_wasmtime(
        store
            .run_concurrent(async |accessor| {
                produce.call_concurrent(&accessor, (mode.input(),)).await
            })
            .await,
    )?)?;

    let snapshot = stats.lock().expect("batched final stats mutex poisoned");
    let expected_result = if mode.sink_error_after().is_some() || mode.hold_call() {
        Err(ErrorCode::Pipe)
    } else {
        Ok(())
    };
    let observed_batches_match = snapshot
        .received
        .iter()
        .map(Vec::as_slice)
        .eq(mode.expected_batches().iter().copied());
    let table_empty = store.data().table.is_empty();
    if result.0 != expected_result
        || !observed_batches_match
        || snapshot.created != 3
        || snapshot.resource_drops != 3
        || snapshot.host_calls != 1
        || snapshot.stream_drops != 1
        || snapshot.future_drops != 1
        || snapshot.pending_polls != u32::from(mode == Mode::Pending)
        || snapshot.cancel_calls != 0
        || !table_empty
    {
        bail!(
            "batched ABI mismatch mode={} result={:?} expected={:?} batches={:?} expected-batches={:?} resource-created={} resource-drops={} list-allocations=2 list-releases=2 stream-drops={} future-drops={} pending-polls={} cancel-calls={} table-empty={}",
            mode.label(),
            result.0,
            expected_result,
            snapshot.received,
            mode.expected_batches(),
            snapshot.created,
            snapshot.resource_drops,
            snapshot.stream_drops,
            snapshot.future_drops,
            snapshot.pending_polls,
            snapshot.cancel_calls,
            table_empty,
        );
    }
    println!(
        "mode={} batches={:?} entries=[111,222];[333] resource-created={} resource-drops={} list-allocations=2 list-releases=2 stream-drops={} future-drops={} pending-polls={} cancel-calls={} table-empty=true result={:?} layout=ptr:{}/{} len:{}/{} stride:{} ticket-offset:{} stream-capacity:{}",
        mode.label(),
        snapshot.received,
        snapshot.created,
        snapshot.resource_drops,
        snapshot.stream_drops,
        snapshot.future_drops,
        snapshot.pending_polls,
        snapshot.cancel_calls,
        result.0,
        LIST_POINTER,
        LIST_POINTER_BATCH1,
        LIST_LENGTH,
        LIST_LENGTH_BATCH1,
        LIST_ELEMENT_STRIDE,
        LIST_TICKET_OFFSET,
        STREAM_CAPACITY,
    );
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: g6_2_batched_list_resource_producer_abi <component.wasm> <mode>")?;
    let mode = Mode::parse(
        &std::env::args()
            .nth(2)
            .context("missing batched producer mode")?,
    )?;
    futures::executor::block_on(run(Path::new(&component_path), mode))
}
