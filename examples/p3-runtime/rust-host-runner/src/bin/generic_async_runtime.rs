use anyhow::{Context, Result, bail};
use futures::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::task::{Context as TaskContext, Poll, Waker};
use std::thread::{self, JoinHandle};
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};

const HOST_INSTANCE: &str = "do:generic-async-runtime-probe/host@0.1.0";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Pending,
    Immediate,
    Cancel,
}

impl Mode {
    fn from_environment() -> Result<Self> {
        match std::env::var("DO_GENERIC_ASYNC_RUNTIME_MODE")
            .unwrap_or_else(|_| "pending".to_owned())
            .as_str()
        {
            "pending" => Ok(Self::Pending),
            "immediate" => Ok(Self::Immediate),
            "cancel" => Ok(Self::Cancel),
            value => bail!(
                "DO_GENERIC_ASYNC_RUNTIME_MODE must be pending, immediate, or cancel, got {value}"
            ),
        }
    }
}

#[derive(Default)]
struct Stats {
    host_calls: AtomicU32,
    polls: AtomicU32,
    external_wakes: AtomicU32,
    host_completions: AtomicU32,
    drops: AtomicU32,
    guest_completed: AtomicBool,
    cancel_before_completion: AtomicU32,
}

struct SignalState {
    armed: bool,
    ready: bool,
    cancelled: bool,
    waker: Option<Waker>,
}

struct WakeSignal {
    state: Mutex<SignalState>,
    changed: Condvar,
}

impl WakeSignal {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::new(SignalState {
                armed: false,
                ready: false,
                cancelled: false,
                waker: None,
            }),
            changed: Condvar::new(),
        })
    }

    fn spawn_external_waker(self: &Arc<Self>, stats: Arc<Stats>) -> JoinHandle<()> {
        let signal = Arc::clone(self);
        thread::spawn(move || {
            let mut state = signal.state.lock().expect("wake signal mutex poisoned");
            while !state.armed && !state.cancelled {
                state = signal
                    .changed
                    .wait(state)
                    .expect("wake signal condvar poisoned");
            }
            if state.cancelled {
                return;
            }
            state.ready = true;
            let waker = state.waker.take();
            stats.external_wakes.fetch_add(1, Ordering::SeqCst);
            drop(state);
            if let Some(waker) = waker {
                waker.wake();
            }
        })
    }

    fn poll(&self, cx: &TaskContext<'_>) -> bool {
        let mut state = self.state.lock().expect("wake signal mutex poisoned");
        if state.ready {
            return true;
        }
        state.armed = true;
        state.waker = Some(cx.waker().clone());
        self.changed.notify_one();
        false
    }

    fn cancel(&self) {
        let mut state = self.state.lock().expect("wake signal mutex poisoned");
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
    external_waker: Option<JoinHandle<()>>,
    immediate: bool,
    completed: bool,
}

impl ControlledWork {
    fn immediate(stats: Arc<Stats>) -> Self {
        Self {
            stats,
            signal: None,
            external_waker: None,
            immediate: true,
            completed: false,
        }
    }

    fn pending(stats: Arc<Stats>, wake_externally: bool) -> Self {
        let signal = wake_externally.then(WakeSignal::new);
        let external_waker = signal
            .as_ref()
            .map(|signal| signal.spawn_external_waker(Arc::clone(&stats)));
        Self {
            stats,
            signal,
            external_waker,
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
        self.stats.host_completions.fetch_add(1, Ordering::SeqCst);
        Poll::Ready(Ok(()))
    }
}

impl Drop for ControlledWork {
    fn drop(&mut self) {
        if !self.completed {
            self.stats.drops.fetch_add(1, Ordering::SeqCst);
            if !self.stats.guest_completed.load(Ordering::SeqCst) {
                self.stats
                    .cancel_before_completion
                    .fetch_add(1, Ordering::SeqCst);
            }
        }
        if let Some(signal) = &self.signal {
            signal.cancel();
        }
        if let Some(external_waker) = self.external_waker.take() {
            external_waker
                .join()
                .expect("external wake thread should terminate");
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:?}"))
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-generic-async-runtime-host-runner <component.wasm>")?;
    let mode = Mode::from_environment()?;
    futures::executor::block_on(run(Path::new(&component_path), mode))
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
        let call = host_stats.host_calls.fetch_add(1, Ordering::SeqCst) + 1;
        let work = match mode {
            Mode::Immediate => ControlledWork::immediate(Arc::clone(&host_stats)),
            Mode::Pending => ControlledWork::pending(Arc::clone(&host_stats), call <= 2),
            Mode::Cancel => {
                if call <= 2 {
                    ControlledWork::immediate(Arc::clone(&host_stats))
                } else {
                    ControlledWork::pending(Arc::clone(&host_stats), false)
                }
            }
        };
        Box::pin(async move { work.await })
    }))?;

    let mut store = Store::new(&engine, ());
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, "run"))?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(accessor, ()).await)
            .await,
    )?;
    map_wasmtime(call)?;
    stats.guest_completed.store(true, Ordering::SeqCst);

    let calls = stats.host_calls.load(Ordering::SeqCst);
    let polls = stats.polls.load(Ordering::SeqCst);
    let external_wakes = stats.external_wakes.load(Ordering::SeqCst);
    let host_completions = stats.host_completions.load(Ordering::SeqCst);
    let drops = stats.drops.load(Ordering::SeqCst);
    let cancel_before_completion = stats.cancel_before_completion.load(Ordering::SeqCst);
    if calls != 3 {
        bail!("expected three host work calls, got {calls}");
    }

    match mode {
        Mode::Pending => {
            if external_wakes != 2 || host_completions != 2 || drops != 1 {
                bail!(
                    "pending observations invalid: polls={polls} external_wakes={external_wakes} host_completions={host_completions} drops={drops}"
                );
            }
            println!("pending external-wakes=2 completions=2 drops=1");
        }
        Mode::Immediate => {
            if external_wakes != 0 || host_completions != 3 || drops != 0 {
                bail!(
                    "immediate observations invalid: polls={polls} external_wakes={external_wakes} host_completions={host_completions} drops={drops}"
                );
            }
            println!("immediate external-wakes=0 completions=3 drops=0");
        }
        Mode::Cancel => {
            if external_wakes != 0
                || host_completions != 2
                || drops != 1
                || cancel_before_completion != 1
            {
                bail!(
                    "cancel observations invalid: polls={polls} external_wakes={external_wakes} host_completions={host_completions} drops={drops} cancel_before_completion={cancel_before_completion}"
                );
            }
            println!("cancel cancel-before-completion=1 completions=2");
        }
    }
    println!(
        "observations calls={calls} polls={polls} host-completions={host_completions} drops={drops}"
    );
    Ok(())
}
