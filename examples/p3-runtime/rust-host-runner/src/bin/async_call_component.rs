use anyhow::{Context, Result, bail};
use futures::future::{Either, Future, select};
use std::path::Path;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::task::{Context as TaskContext, Poll, Waker};
use std::thread::{self, JoinHandle};
use wasmtime::component::{Component, Linker, ResourceTable};
use wasmtime::{Config, Engine, Store};

const HOST_INSTANCE: &str = "do:generic-async-call-probe/host@0.1.0";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Ready,
    Pending,
    Cancel,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "ready" => Ok(Self::Ready),
            "pending" => Ok(Self::Pending),
            "cancel" => Ok(Self::Cancel),
            other => bail!("mode must be ready, pending, or cancel, got {other}"),
        }
    }

}

#[derive(Default)]
struct Stats {
    host_calls: AtomicU32,
    polls: AtomicU32,
    wakes: AtomicU32,
    completions: AtomicU32,
    future_drops: AtomicU32,
    pending_future_drops: AtomicU32,
    guest_completed: AtomicBool,
}

struct WakeState {
    armed: bool,
    ready: bool,
    cancelled: bool,
    waker: Option<Waker>,
}

struct WakeSignal {
    state: Mutex<WakeState>,
    changed: Condvar,
}

impl WakeSignal {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::new(WakeState {
                armed: false,
                ready: false,
                cancelled: false,
                waker: None,
            }),
            changed: Condvar::new(),
        })
    }

    fn spawn(self: &Arc<Self>, stats: Arc<Stats>) -> JoinHandle<()> {
        let signal = Arc::clone(self);
        thread::spawn(move || {
            let mut state = signal.state.lock().expect("async-call wake mutex poisoned");
            while !state.armed && !state.cancelled {
                state = signal
                    .changed
                    .wait(state)
                    .expect("async-call wake condvar poisoned");
            }
            if state.cancelled {
                return;
            }
            state.ready = true;
            let waker = state.waker.take();
            stats.wakes.fetch_add(1, Ordering::SeqCst);
            drop(state);
            if let Some(waker) = waker {
                waker.wake();
            }
        })
    }

    fn poll(&self, cx: &TaskContext<'_>) -> bool {
        let mut state = self.state.lock().expect("async-call wake mutex poisoned");
        if state.ready {
            return true;
        }
        state.armed = true;
        state.waker = Some(cx.waker().clone());
        self.changed.notify_one();
        false
    }

    fn cancel(&self) {
        let mut state = self.state.lock().expect("async-call wake mutex poisoned");
        state.cancelled = true;
        let waker = state.waker.take();
        self.changed.notify_one();
        drop(state);
        if let Some(waker) = waker {
            waker.wake();
        }
    }
}

struct ControlledWork {
    stats: Arc<Stats>,
    signal: Option<Arc<WakeSignal>>,
    waker_thread: Option<JoinHandle<()>>,
    immediate: bool,
    completed: bool,
}

impl ControlledWork {
    fn ready(stats: Arc<Stats>) -> Self {
        Self {
            stats,
            signal: None,
            waker_thread: None,
            immediate: true,
            completed: false,
        }
    }

    fn pending(stats: Arc<Stats>, wake: bool) -> Self {
        let signal = Some(WakeSignal::new());
        let waker_thread = signal
            .as_ref()
            .filter(|_| wake)
            .map(|signal| signal.spawn(Arc::clone(&stats)));
        Self {
            stats,
            signal,
            waker_thread,
            immediate: false,
            completed: false,
        }
    }
}

impl Future for ControlledWork {
    type Output = wasmtime::Result<()>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        self.stats.polls.fetch_add(1, Ordering::SeqCst);
        let ready = self.immediate || self.signal.as_ref().is_some_and(|signal| signal.poll(cx));
        if !ready {
            return Poll::Pending;
        }
        self.completed = true;
        self.stats.completions.fetch_add(1, Ordering::SeqCst);
        Poll::Ready(Ok(()))
    }
}

impl Drop for ControlledWork {
    fn drop(&mut self) {
        self.stats.future_drops.fetch_add(1, Ordering::SeqCst);
        if !self.completed {
            self.stats.pending_future_drops.fetch_add(1, Ordering::SeqCst);
        }
        if let Some(signal) = &self.signal {
            signal.cancel();
        }
        if let Some(thread) = self.waker_thread.take() {
            thread
                .join()
                .expect("async-call external waker should terminate");
        }
    }
}

struct CancelAfterHostCall {
    stats: Arc<Stats>,
}

impl Future for CancelAfterHostCall {
    type Output = ();

    fn poll(self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        if self.stats.host_calls.load(Ordering::SeqCst) != 0 {
            Poll::Ready(())
        } else {
            cx.waker().wake_by_ref();
            Poll::Pending
        }
    }
}

struct State {
    table: ResourceTable,
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

async fn invoke(
    store: &mut Store<State>,
    run: &wasmtime::component::TypedFunc<(), ()>,
    stats: Arc<Stats>,
    mode: Mode,
) -> Result<()> {
    let call = store.run_concurrent(async |accessor| run.call_concurrent(accessor, ()).await);
    match mode {
        Mode::Cancel => {
            let cancel = CancelAfterHostCall { stats };
            match select(Box::pin(call), Box::pin(cancel)).await {
                Either::Left((result, _cancel)) => {
                    let result = map_wasmtime(result)?;
                    map_wasmtime(result)?;
                    bail!("cancel mode completed the root task before cancellation");
                }
                Either::Right((_cancel, pending_call)) => drop(pending_call),
            }
        }
        Mode::Ready | Mode::Pending => {
            let result = map_wasmtime(call.await)?;
            map_wasmtime(result)?;
        }
    }
    Ok(())
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
    let stats = Arc::new(Stats::default());
    let mut linker = Linker::new(&engine);
    let mut host = map_wasmtime(linker.instance(HOST_INSTANCE))?;
    let host_stats = Arc::clone(&stats);
    map_wasmtime(host.func_wrap_concurrent("work", move |_accessor, ()| {
        host_stats.host_calls.fetch_add(1, Ordering::SeqCst);
        let work = match mode {
            Mode::Ready => ControlledWork::ready(Arc::clone(&host_stats)),
            Mode::Pending => ControlledWork::pending(Arc::clone(&host_stats), true),
            Mode::Cancel => ControlledWork::pending(Arc::clone(&host_stats), false),
        };
        Box::pin(async move { work.await })
    }))?;

    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, "run"))?;
    invoke(&mut store, &run, Arc::clone(&stats), mode).await?;
    if mode != Mode::Cancel {
        stats.guest_completed.store(true, Ordering::SeqCst);
    }
    let table_empty = store.data().table.is_empty();
    drop(store);

    let calls = stats.host_calls.load(Ordering::SeqCst);
    let polls = stats.polls.load(Ordering::SeqCst);
    let wakes = stats.wakes.load(Ordering::SeqCst);
    let completions = stats.completions.load(Ordering::SeqCst);
    let drops = stats.future_drops.load(Ordering::SeqCst);
    let pending_drops = stats.pending_future_drops.load(Ordering::SeqCst);
    let guest_completed = stats.guest_completed.load(Ordering::SeqCst);
    match mode {
        Mode::Ready => {
            if calls != 1 || polls != 1 || wakes != 0 || completions != 1 || drops != 1 ||
                pending_drops != 0 || !guest_completed || !table_empty
            {
                bail!("ready observations invalid: calls={calls} polls={polls} wakes={wakes} completions={completions} drops={drops} pending-drops={pending_drops} guest-completed={guest_completed} table-empty={table_empty}");
            }
            println!("mode=ready child-completions=1 child-drops=1 host-future-drops=1 table-empty=true");
        }
        Mode::Pending => {
            if calls != 1 || polls < 2 || wakes != 1 || completions != 1 || drops != 1 ||
                pending_drops != 0 || !guest_completed || !table_empty
            {
                bail!("pending observations invalid: calls={calls} polls={polls} wakes={wakes} completions={completions} drops={drops} pending-drops={pending_drops} guest-completed={guest_completed} table-empty={table_empty}");
            }
            println!("mode=pending child-completions=1 child-drops=1 host-future-drops=1 table-empty=true");
        }
        Mode::Cancel => {
            if calls != 1 || polls < 1 || wakes != 0 || completions != 0 || drops != 1 ||
                pending_drops != 1 || guest_completed || !table_empty
            {
                bail!("cancel observations invalid: calls={calls} polls={polls} wakes={wakes} completions={completions} drops={drops} pending-drops={pending_drops} guest-completed={guest_completed} table-empty={table_empty}");
            }
            println!("mode=cancel child-cancellations=1 child-drops=1 host-future-drops=1 table-empty=true");
        }
    }
    println!("async-call root-terminal=1 duplicate-drop=0");
    Ok(())
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: do-p3-async-call-component-host-runner <component.wasm> <ready|pending|cancel>")?;
    let mode = args
        .next()
        .context("usage: do-p3-async-call-component-host-runner <component.wasm> <ready|pending|cancel>")?;
    if args.next().is_some() {
        bail!("usage: do-p3-async-call-component-host-runner <component.wasm> <ready|pending|cancel>");
    }
    futures::executor::block_on(run(Path::new(&component_path), Mode::parse(&mode)?))
}
