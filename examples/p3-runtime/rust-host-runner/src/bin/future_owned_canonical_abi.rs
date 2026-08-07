use anyhow::{Context, Result, bail};
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, FutureProducer, FutureReader, Linker, Resource, ResourceTable, ResourceType,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const SOURCE_INSTANCE: &str = "do:future-owned-canonical/source@0.1.0";
const PROBE_INSTANCE: &str = "do:future-owned-canonical/probe@0.1.0";
const PAYLOAD_OFFSET: u32 = 12;
const TICKET_PRESENT_OFFSET: u32 = 20;

pub struct Ticket {
    _value: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Ready,
    Pending,
    Cancel,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "0" | "ready" => Ok(Self::Ready),
            "1" | "pending" => Ok(Self::Pending),
            "2" | "cancel" => Ok(Self::Cancel),
            other => bail!("mode must be 0/1/2 or ready/pending/cancel, got {other}"),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Ready => "ready",
            Self::Pending => "pending",
            Self::Cancel => "cancel",
        }
    }
}

#[derive(Default)]
struct Stats {
    host_calls: u32,
    polls: u32,
    wakes: u32,
    cancel_calls: u32,
    future_drops: u32,
    pending_future_drops: u32,
    resource_created: u32,
    resource_drops: u32,
}

struct State {
    table: ResourceTable,
}

struct OwnedTicketFuture {
    stats: Arc<Mutex<Stats>>,
    mode: Mode,
    pending_once: bool,
    completed: bool,
}

impl FutureProducer<State> for OwnedTicketFuture {
    type Item = Resource<Ticket>;

    fn poll_produce(
        mut self: Pin<&mut Self>,
        cx: &mut TaskContext<'_>,
        mut store: StoreContextMut<'_, State>,
        finish: bool,
    ) -> Poll<wasmtime::Result<Option<Self::Item>>> {
        if finish {
            self.stats
                .lock()
                .expect("future-owned stats mutex poisoned")
                .cancel_calls += 1;
            return Poll::Ready(Ok(None));
        }

        self.stats
            .lock()
            .expect("future-owned stats mutex poisoned")
            .polls += 1;

        if self.mode == Mode::Cancel {
            return Poll::Pending;
        }
        if self.mode == Mode::Pending && !self.pending_once {
            self.pending_once = true;
            {
                let mut stats = self
                    .stats
                    .lock()
                    .expect("future-owned stats mutex poisoned");
                stats.wakes += 1;
            }
            cx.waker().wake_by_ref();
            return Poll::Pending;
        }

        let ticket = store.data_mut().table.push(Ticket { _value: 111 })?;
        self.stats
            .lock()
            .expect("future-owned stats mutex poisoned")
            .resource_created += 1;
        self.completed = true;
        Poll::Ready(Ok(Some(ticket)))
    }
}

impl Drop for OwnedTicketFuture {
    fn drop(&mut self) {
        let mut stats = self
            .stats
            .lock()
            .expect("future-owned stats mutex poisoned");
        stats.future_drops += 1;
        if !self.completed {
            stats.pending_future_drops += 1;
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn install_source(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    mode: Mode,
) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_INSTANCE)?;
    let drop_stats = Arc::clone(&stats);
    source.resource(
        "ticket",
        ResourceType::host::<Ticket>(),
        move |mut store, rep| {
            store
                .data_mut()
                .table
                .delete(Resource::<Ticket>::new_own(rep))?;
            drop_stats
                .lock()
                .expect("future-owned resource stats mutex poisoned")
                .resource_drops += 1;
            Ok(())
        },
    )?;

    let read_stats = Arc::clone(&stats);
    source.func_wrap("read", move |mut store, ()| {
        read_stats
            .lock()
            .expect("future-owned source stats mutex poisoned")
            .host_calls += 1;
        let future = FutureReader::new(
            &mut store,
            OwnedTicketFuture {
                stats: Arc::clone(&read_stats),
                mode,
                pending_once: false,
                completed: false,
            },
        )?;
        Ok((future,))
    })?;
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
        .context("missing future-owned probe export")?;
    let run = instance
        .get_export_index(&mut store, Some(&probe), "run")
        .context("missing future-owned probe.run export")?;
    let run = map_wasmtime(instance.get_typed_func::<(u32,), ()>(&mut store, &run))?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, (mode as u32,)).await)
            .await,
    )?;
    map_wasmtime(call)?;

    let snapshot = stats.lock().expect("future-owned stats mutex poisoned");
    let expected_polls = match mode {
        Mode::Ready | Mode::Cancel => 1,
        Mode::Pending => 2,
    };
    let expected_wakes = u32::from(mode == Mode::Pending);
    let expected_created = u32::from(mode != Mode::Cancel);
    let expected_drops = expected_created;
    let expected_pending_drops = u32::from(mode == Mode::Cancel);
    if snapshot.host_calls != 1
        || snapshot.polls != expected_polls
        || snapshot.wakes != expected_wakes
        || snapshot.cancel_calls != u32::from(mode == Mode::Cancel)
        || snapshot.future_drops != 1
        || snapshot.pending_future_drops != expected_pending_drops
        || snapshot.resource_created != expected_created
        || snapshot.resource_drops != expected_drops
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected future-owned stats: mode={} host-calls={} polls={} wakes={} cancel-calls={} future-drops={} pending-future-drops={} resource-created={} resource-drops={} table-empty={}",
            mode.name(),
            snapshot.host_calls,
            snapshot.polls,
            snapshot.wakes,
            snapshot.cancel_calls,
            snapshot.future_drops,
            snapshot.pending_future_drops,
            snapshot.resource_created,
            snapshot.resource_drops,
            store.data().table.is_empty(),
        );
    }
    println!(
        "mode={} host-calls={} polls={} wakes={} cancel-calls={} future-drops={} pending-future-drops={} resource-created={} resource-drops={} table-empty={} observed-payload-offset={} observed-ticket-present-offset={}",
        mode.name(),
        snapshot.host_calls,
        snapshot.polls,
        snapshot.wakes,
        snapshot.cancel_calls,
        snapshot.future_drops,
        snapshot.pending_future_drops,
        snapshot.resource_created,
        snapshot.resource_drops,
        store.data().table.is_empty(),
        PAYLOAD_OFFSET,
        TICKET_PRESENT_OFFSET,
    );
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: do-p3-future-owned-canonical-abi <component.wasm> <mode>")?;
    let mode = args
        .next()
        .context("usage: do-p3-future-owned-canonical-abi <component.wasm> <mode>")?;
    if args.next().is_some() {
        bail!("usage: do-p3-future-owned-canonical-abi <component.wasm> <mode>");
    }
    futures::executor::block_on(run(Path::new(&component_path), Mode::parse(&mode)?))
}
