use anyhow::{Context, Result, bail};
use futures::channel::oneshot;
use futures::future::{BoxFuture, Either, select};
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{AccessorTask, Component, Linker};
use wasmtime::{Config, Engine, Store};

const FIRST_DEADLINE: u64 = 27_815;
const SECOND_DEADLINE: u64 = 27_182;
const LOOP_PARAMETER_FIRST: u64 = 2;
const LOOP_PARAMETER_SECOND: u64 = 3;
const LOOP_PARAMETER_ADD_FIRST: u64 = 1;
const LOOP_PARAMETER_ADD_SECOND: u64 = 2;
const LOOP_PRE_GUARD_FIRST: u64 = 0;
const LOOP_PRE_GUARD_SECOND: u64 = 2;
const CLOCK_INSTANCE: &str = "wasi:clocks/monotonic-clock@0.3.0";

#[derive(Clone, Copy)]
enum Shape {
    TwoAwait,
    ThreeAwait,
    IfBranch,
    IfJoin,
    LoopCountdown,
    LoopCountdownParameter,
    LoopCountdownParameterAdd,
    LoopCountdownCounterArgument,
    LoopCountdownPreGuard,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum LifecycleMode {
    Ready,
    Pending,
    Error,
    Cancel,
    EarlyDrop,
    Repeat,
}

impl LifecycleMode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "--ready" => Ok(Self::Ready),
            "--pending" => Ok(Self::Pending),
            "--error" => Ok(Self::Error),
            "--cancel" => Ok(Self::Cancel),
            "--early-drop" => Ok(Self::EarlyDrop),
            "--repeat" => Ok(Self::Repeat),
            other => bail!("unknown lifecycle mode: {other}"),
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error}"))
}

#[derive(Default)]
struct Stats {
    calls: Vec<(&'static str, u64)>,
    pending_polls: u32,
    external_wakes: u32,
    completions: u32,
    host_errors: u32,
}

struct ClockWait {
    stats: Arc<Mutex<Stats>>,
    completion: oneshot::Receiver<()>,
    pending_recorded: bool,
}

struct CancelAfterHostCalls {
    stats: Arc<Mutex<Stats>>,
    required_calls: usize,
}

impl Future for CancelAfterHostCalls {
    type Output = ();

    fn poll(self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        if self
            .stats
            .lock()
            .expect("two-await lifecycle stats mutex poisoned")
            .calls
            .len()
            >= self.required_calls
        {
            Poll::Ready(())
        } else {
            cx.waker().wake_by_ref();
            Poll::Pending
        }
    }
}

impl Future for ClockWait {
    type Output = wasmtime::Result<()>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        match Pin::new(&mut self.completion).poll(cx) {
            Poll::Pending => {
                if self.pending_recorded {
                    return Poll::Pending;
                }
                self.pending_recorded = true;
                self.stats
                    .lock()
                    .expect("two-await stats mutex poisoned")
                    .pending_polls += 1;
                Poll::Pending
            }
            Poll::Ready(Ok(())) => {
                self.stats
                    .lock()
                    .expect("two-await stats mutex poisoned")
                    .completions += 1;
                Poll::Ready(Ok(()))
            }
            Poll::Ready(Err(_)) => {
                Poll::Ready(Err(wasmtime::Error::msg("clock host event dropped")))
            }
        }
    }
}

struct HostWake {
    stats: Arc<Mutex<Stats>>,
    completion: oneshot::Sender<()>,
}

struct ReadyHost {
    stats: Arc<Mutex<Stats>>,
}

impl ReadyHost {
    fn task(self) -> impl for<'a> AccessorTask<'a, ()> {
        async move |_accessor| {
            self.stats
                .lock()
                .expect("two-await stats mutex poisoned")
                .completions += 1;
            Ok(())
        }
    }
}

impl HostWake {
    fn task(self) -> impl for<'a> AccessorTask<'a, ()> {
        async move |_accessor| {
            self.stats
                .lock()
                .expect("two-await stats mutex poisoned")
                .external_wakes += 1;
            let _ = self.completion.send(());
            Ok(())
        }
    }
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: do-p3-two-await-host-runner <component.wasm>")?;
    let mode = args.next();
    let lifecycle = mode
        .as_deref()
        .filter(|value| {
            value.starts_with("--")
                && !value.starts_with("--three-await")
                && !value.starts_with("--if-")
                && !value.starts_with("--loop-")
        })
        .map(LifecycleMode::parse)
        .transpose()?;
    let shape = match mode.as_deref() {
        None => Shape::TwoAwait,
        Some("--three-await") => Shape::ThreeAwait,
        Some("--if-branch") => Shape::IfBranch,
        Some("--if-join") => Shape::IfJoin,
        Some("--loop-countdown") => Shape::LoopCountdown,
        Some("--loop-countdown-parameter") => Shape::LoopCountdownParameter,
        Some("--loop-countdown-parameter-add") => Shape::LoopCountdownParameterAdd,
        Some("--loop-countdown-counter-argument") => Shape::LoopCountdownCounterArgument,
        Some("--loop-countdown-pre-guard") => Shape::LoopCountdownPreGuard,
        Some(_value) if lifecycle.is_some() => {
            if args.next().is_some() {
                bail!("lifecycle mode accepts exactly one mode argument")
            }
            return futures::executor::block_on(run_with_mode(
                Path::new(&component_path),
                Shape::TwoAwait,
                lifecycle,
            ));
        }
        Some(_) => bail!(
            "usage: do-p3-two-await-host-runner <component.wasm> [--three-await|--if-branch|--if-join|--loop-countdown|--loop-countdown-parameter|--loop-countdown-parameter-add|--loop-countdown-counter-argument|--loop-countdown-pre-guard|--ready|--pending|--error|--cancel|--early-drop|--repeat]"
        ),
    };
    if args.next().is_some() {
        bail!(
            "usage: do-p3-two-await-host-runner <component.wasm> [--three-await|--if-branch|--if-join|--loop-countdown|--loop-countdown-parameter|--loop-countdown-parameter-add|--loop-countdown-counter-argument|--loop-countdown-pre-guard]"
        );
    }
    futures::executor::block_on(run_with_mode(Path::new(&component_path), shape, None))
}

async fn run_with_mode(
    component_path: &Path,
    shape: Shape,
    lifecycle: Option<LifecycleMode>,
) -> Result<()> {
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
    let mut clock = map_wasmtime(linker.instance(CLOCK_INSTANCE))?;
    let lifecycle_mode = lifecycle;

    let wait_for_stats = Arc::clone(&stats);
    map_wasmtime(clock.func_wrap_concurrent(
        "wait-for",
        move |accessor, (deadline,): (u64,)| -> BoxFuture<'_, wasmtime::Result<()>> {
            let mut stats = wait_for_stats
                .lock()
                .expect("two-await stats mutex poisoned");
            stats.calls.push(("wait-for", deadline));
            drop(stats);
            match lifecycle_mode {
                Some(LifecycleMode::Ready) => {
                    let host_event = accessor.spawn(
                        ReadyHost {
                            stats: Arc::clone(&wait_for_stats),
                        }
                        .task(),
                    );
                    return Box::pin(async move {
                        host_event?;
                        Ok(())
                    });
                }
                Some(LifecycleMode::Error) => {
                    wait_for_stats
                        .lock()
                        .expect("two-await stats mutex poisoned")
                        .host_errors += 1;
                    return Box::pin(async {
                        Err(wasmtime::Error::msg("two-await lifecycle host error"))
                    });
                }
                _ => {}
            }
            if matches!(
                lifecycle_mode,
                Some(LifecycleMode::Cancel | LifecycleMode::EarlyDrop)
            ) {
                let (keep_alive, completion) = oneshot::channel();
                let wait = ClockWait {
                    stats: Arc::clone(&wait_for_stats),
                    completion,
                    pending_recorded: false,
                };
                return Box::pin(async move {
                    let _keep_alive = keep_alive;
                    wait.await
                });
            }
            let (completion_sender, completion) = oneshot::channel();
            let host_event = accessor.spawn(
                HostWake {
                    stats: Arc::clone(&wait_for_stats),
                    completion: completion_sender,
                }
                .task(),
            );
            let wait = ClockWait {
                stats: Arc::clone(&wait_for_stats),
                completion,
                pending_recorded: false,
            };
            Box::pin(async move {
                host_event?;
                wait.await
            })
        },
    ))?;

    let wait_until_stats = Arc::clone(&stats);
    map_wasmtime(clock.func_wrap_concurrent(
        "wait-until",
        move |accessor, (deadline,): (u64,)| -> BoxFuture<'_, wasmtime::Result<()>> {
            let mut stats = wait_until_stats
                .lock()
                .expect("two-await stats mutex poisoned");
            stats.calls.push(("wait-until", deadline));
            drop(stats);
            match lifecycle_mode {
                Some(LifecycleMode::Ready) => {
                    let host_event = accessor.spawn(
                        ReadyHost {
                            stats: Arc::clone(&wait_until_stats),
                        }
                        .task(),
                    );
                    return Box::pin(async move {
                        host_event?;
                        Ok(())
                    });
                }
                Some(LifecycleMode::Error) => {
                    wait_until_stats
                        .lock()
                        .expect("two-await stats mutex poisoned")
                        .host_errors += 1;
                    return Box::pin(async {
                        Err(wasmtime::Error::msg("two-await lifecycle host error"))
                    });
                }
                _ => {}
            }
            if matches!(
                lifecycle_mode,
                Some(LifecycleMode::Cancel | LifecycleMode::EarlyDrop)
            ) {
                let (keep_alive, completion) = oneshot::channel();
                let wait = ClockWait {
                    stats: Arc::clone(&wait_until_stats),
                    completion,
                    pending_recorded: false,
                };
                return Box::pin(async move {
                    let _keep_alive = keep_alive;
                    wait.await
                });
            }
            let (completion_sender, completion) = oneshot::channel();
            let host_event = accessor.spawn(
                HostWake {
                    stats: Arc::clone(&wait_until_stats),
                    completion: completion_sender,
                }
                .task(),
            );
            let wait = ClockWait {
                stats: Arc::clone(&wait_until_stats),
                completion,
                pending_recorded: false,
            };
            Box::pin(async move {
                host_event?;
                wait.await
            })
        },
    ))?;

    let mut store = Store::new(&engine, ());
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(instance.get_typed_func::<(u64,), ()>(&mut store, "run"))?;
    let (first_input, second_input) = match shape {
        Shape::LoopCountdownParameter | Shape::LoopCountdownCounterArgument => {
            (LOOP_PARAMETER_FIRST, LOOP_PARAMETER_SECOND)
        }
        Shape::LoopCountdownParameterAdd => (LOOP_PARAMETER_ADD_FIRST, LOOP_PARAMETER_ADD_SECOND),
        Shape::LoopCountdownPreGuard => (LOOP_PRE_GUARD_FIRST, LOOP_PRE_GUARD_SECOND),
        _ => (FIRST_DEADLINE, SECOND_DEADLINE),
    };
    if let Some(mode) = lifecycle {
        match mode {
            LifecycleMode::Ready | LifecycleMode::Pending => {
                if mode == LifecycleMode::Ready {
                    let call = map_wasmtime(
                        store
                            .run_concurrent(async |accessor| {
                                run.call_concurrent(&accessor, (first_input,)).await
                            })
                            .await,
                    )?;
                    map_wasmtime(call)?;
                } else {
                    let pair = map_wasmtime(
                        store
                            .run_concurrent(async |accessor| {
                                futures::try_join!(
                                    run.call_concurrent(&accessor, (first_input,)),
                                    run.call_concurrent(&accessor, (second_input,)),
                                )
                                .map(|_| ())
                            })
                            .await,
                    )?;
                    map_wasmtime(pair)?;
                }
            }
            LifecycleMode::Error => {
                for input in [first_input, second_input] {
                    let outer = store
                        .run_concurrent(async |accessor| {
                            run.call_concurrent(&accessor, (input,)).await
                        })
                        .await;
                    if let Ok(inner) = outer {
                        if inner.is_ok() {
                            bail!("two-await lifecycle error unexpectedly completed");
                        }
                    }
                }
            }
            LifecycleMode::Cancel => {
                let call = store.run_concurrent(async |accessor| {
                    run.call_concurrent(&accessor, (first_input,)).await
                });
                let cancel = CancelAfterHostCalls {
                    stats: Arc::clone(&stats),
                    required_calls: 1,
                };
                match select(Box::pin(call), Box::pin(cancel)).await {
                    Either::Left((result, _cancel)) => {
                        let result = map_wasmtime(result)?;
                        map_wasmtime(result)?;
                        bail!("two-await cancel mode completed before cancellation");
                    }
                    Either::Right((_cancel, pending_call)) => drop(pending_call),
                }
            }
            LifecycleMode::EarlyDrop => {
                let call = store.run_concurrent(async |accessor| {
                    run.call_concurrent(&accessor, (first_input,)).await
                });
                drop(call);
            }
            LifecycleMode::Repeat => {
                for _ in 0..2 {
                    let pair = map_wasmtime(
                        store
                            .run_concurrent(async |accessor| {
                                futures::try_join!(
                                    run.call_concurrent(&accessor, (first_input,)),
                                    run.call_concurrent(&accessor, (second_input,)),
                                )
                                .map(|_| ())
                            })
                            .await,
                    )?;
                    map_wasmtime(pair)?;
                }
            }
        }

        let stats = stats
            .lock()
            .expect("two-await lifecycle stats mutex poisoned");
        match mode {
            LifecycleMode::Ready => {
                if stats.calls.len() != 2
                    || stats.pending_polls != 0
                    || stats.external_wakes != 0
                    || stats.completions != 2
                    || stats.host_errors != 0
                {
                    bail!(
                        "ready lifecycle observations invalid: calls={} pending-polls={} external-wakes={} completions={} host-errors={}",
                        stats.calls.len(),
                        stats.pending_polls,
                        stats.external_wakes,
                        stats.completions,
                        stats.host_errors,
                    );
                }
                println!(
                    "future lifecycle case=ready pending-polls=0 external-wakes=0 completions=2"
                );
            }
            LifecycleMode::Pending => {
                if stats.calls.len() != 4
                    || stats.pending_polls != 4
                    || stats.external_wakes != 4
                    || stats.completions != 4
                    || stats.host_errors != 0
                {
                    bail!(
                        "pending lifecycle observations invalid: calls={} pending-polls={} external-wakes={} completions={} host-errors={}",
                        stats.calls.len(),
                        stats.pending_polls,
                        stats.external_wakes,
                        stats.completions,
                        stats.host_errors,
                    );
                }
                println!(
                    "future lifecycle case=pending pending-polls=4 external-wakes=4 completions=4"
                );
            }
            LifecycleMode::Error => {
                if stats.host_errors != 1 || stats.completions != 0 {
                    bail!(
                        "error lifecycle observations invalid: host-errors={} completions={}",
                        stats.host_errors,
                        stats.completions,
                    );
                }
                println!("future lifecycle case=error host-errors=1 completions=0");
            }
            LifecycleMode::Cancel => {
                if stats.calls.len() != 1 || stats.pending_polls == 0 || stats.completions != 0 {
                    bail!(
                        "cancel lifecycle observations invalid: calls={} pending-polls={} completions={}",
                        stats.calls.len(),
                        stats.pending_polls,
                        stats.completions,
                    );
                }
                println!("future lifecycle case=cancel host-calls=1 cancelled=1");
            }
            LifecycleMode::EarlyDrop => {
                if !stats.calls.is_empty()
                    || stats.pending_polls != 0
                    || stats.external_wakes != 0
                    || stats.completions != 0
                {
                    bail!(
                        "early-drop lifecycle observations invalid: calls={} pending-polls={} external-wakes={} completions={}",
                        stats.calls.len(),
                        stats.pending_polls,
                        stats.external_wakes,
                        stats.completions,
                    );
                }
                println!("future lifecycle case=early-drop host-calls=0 cancelled=1");
            }
            LifecycleMode::Repeat => {
                if stats.calls.len() != 8
                    || stats.pending_polls != 8
                    || stats.external_wakes != 8
                    || stats.completions != 8
                {
                    bail!(
                        "repeat lifecycle observations invalid: calls={} pending-polls={} external-wakes={} completions={}",
                        stats.calls.len(),
                        stats.pending_polls,
                        stats.external_wakes,
                        stats.completions,
                    );
                }
                println!(
                    "future lifecycle case=repeat runs=2 pending-polls=8 external-wakes=8 completions=8"
                );
            }
        }
        return Ok(());
    }
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| {
                futures::try_join!(
                    run.call_concurrent(&accessor, (first_input,)),
                    run.call_concurrent(&accessor, (second_input,)),
                )
                .map(|_| ())
            })
            .await,
    )?;
    map_wasmtime(call)?;

    let stats = stats.lock().expect("two-await stats mutex poisoned");
    let expected_wait_for_calls = if matches!(shape, Shape::ThreeAwait | Shape::LoopCountdown) {
        2
    } else {
        1
    };
    let expected_total = match shape {
        Shape::TwoAwait => 4,
        Shape::ThreeAwait => 6,
        Shape::IfBranch => 2,
        Shape::IfJoin => 4,
        Shape::LoopCountdown => 4,
        Shape::LoopCountdownParameter => 5,
        Shape::LoopCountdownParameterAdd => 5,
        Shape::LoopCountdownCounterArgument => 5,
        Shape::LoopCountdownPreGuard => 2,
    };
    let expected_deadlines: &[u64] = match shape {
        Shape::LoopCountdownCounterArgument | Shape::LoopCountdownPreGuard => &[1, second_input],
        _ => &[first_input, second_input],
    };
    for &deadline in expected_deadlines {
        for operation in ["wait-for", "wait-until"] {
            let expected = match shape {
                Shape::IfBranch if deadline == FIRST_DEADLINE && operation == "wait-for" => 1,
                Shape::IfBranch if deadline == SECOND_DEADLINE && operation == "wait-until" => 1,
                Shape::IfBranch => 0,
                Shape::IfJoin if deadline == FIRST_DEADLINE && operation == "wait-for" => 2,
                Shape::IfJoin
                    if deadline == SECOND_DEADLINE
                        && (operation == "wait-for" || operation == "wait-until") =>
                {
                    1
                }
                Shape::IfJoin => 0,
                Shape::LoopCountdown if operation == "wait-for" => 2,
                Shape::LoopCountdown => 0,
                Shape::LoopCountdownParameter
                    if operation == "wait-for" && deadline == LOOP_PARAMETER_FIRST =>
                {
                    2
                }
                Shape::LoopCountdownParameter
                    if operation == "wait-for" && deadline == LOOP_PARAMETER_SECOND =>
                {
                    3
                }
                Shape::LoopCountdownParameter => 0,
                Shape::LoopCountdownParameterAdd
                    if operation == "wait-for" && deadline == LOOP_PARAMETER_ADD_FIRST =>
                {
                    2
                }
                Shape::LoopCountdownParameterAdd
                    if operation == "wait-for" && deadline == LOOP_PARAMETER_ADD_SECOND =>
                {
                    3
                }
                Shape::LoopCountdownParameterAdd => 0,
                Shape::LoopCountdownCounterArgument if operation == "wait-for" && deadline == 1 => {
                    2
                }
                Shape::LoopCountdownCounterArgument
                    if operation == "wait-for" && deadline == LOOP_PARAMETER_FIRST =>
                {
                    2
                }
                Shape::LoopCountdownCounterArgument
                    if operation == "wait-for" && deadline == LOOP_PARAMETER_SECOND =>
                {
                    1
                }
                Shape::LoopCountdownCounterArgument => 0,
                Shape::LoopCountdownPreGuard
                    if operation == "wait-for"
                        && (deadline == 1 || deadline == LOOP_PRE_GUARD_SECOND) =>
                {
                    1
                }
                Shape::LoopCountdownPreGuard => 0,
                _ if operation == "wait-for" => expected_wait_for_calls,
                _ => 1,
            };
            let matches = stats
                .calls
                .iter()
                .filter(|call| **call == (operation, deadline))
                .count();
            if matches != expected {
                bail!(
                    "expected {expected} {operation} calls for deadline {deadline}, got calls={:?}",
                    stats.calls
                );
            }
        }
    }
    if stats.calls.len() != expected_total
        || stats.pending_polls != expected_total as u32
        || stats.external_wakes != expected_total as u32
        || stats.completions != expected_total as u32
    {
        bail!(
            "expected {expected_total} calls, pending polls, external wakes, and completions; got calls={:?} pending={} wakes={} completions={}",
            stats.calls,
            stats.pending_polls,
            stats.external_wakes,
            stats.completions
        );
    }

    let shape_name = match shape {
        Shape::TwoAwait => "two-await",
        Shape::ThreeAwait => "three-await",
        Shape::IfBranch => "if-branch",
        Shape::IfJoin => "if-join",
        Shape::LoopCountdown => "loop-countdown",
        Shape::LoopCountdownParameter => "loop-countdown-parameter",
        Shape::LoopCountdownParameterAdd => "loop-countdown-parameter-add",
        Shape::LoopCountdownCounterArgument => "loop-countdown-counter-argument",
        Shape::LoopCountdownPreGuard => "loop-countdown-pre-guard",
    };
    println!("Rust P3 {shape_name} adapter passed");
    println!("clock parallel-calls=2");
    println!("clock pending-polls={}", stats.pending_polls);
    println!("clock external-wakes={}", stats.external_wakes);
    println!("clock completions={}", stats.completions);
    Ok(())
}
