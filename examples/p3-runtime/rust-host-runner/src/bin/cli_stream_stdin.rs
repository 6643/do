use anyhow::{Context, Result, bail};
use std::future::Future;
use std::io::{Read, Write};
use std::mem;
#[cfg(unix)]
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use std::thread;
use wasmtime::component::{
    Component, Destination, FutureReader, Linker, StreamProducer, StreamReader, StreamResult,
    VecBuffer,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

#[path = "../budget_gate.rs"]
mod budget_gate;

const CLI_STDIN_INSTANCE: &str = "wasi:cli/stdin@0.3.0-rc-2025-09-16";
const CLI_TYPES_INSTANCE: &str = "wasi:cli/types@0.3.0-rc-2025-09-16";
const CLI_STDIN_FRAME_BYTES: u64 = 32;

wasmtime::component::bindgen!({
    path: "../wit/cli-stream-stdin.wit",
    world: "stream-stdin-probe",
});

#[derive(Default)]
struct State;

#[derive(Default)]
struct Stats {
    items: Vec<u8>,
    provider_calls: u32,
    completion_polls: u32,
    stream_dropped: bool,
    future_dropped: bool,
}

struct RecordingStream {
    stats: Arc<Mutex<Stats>>,
    items: Vec<u8>,
}

impl Drop for RecordingStream {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("CLI stdin stats mutex poisoned")
            .stream_dropped = true;
    }
}

impl StreamProducer<State> for RecordingStream {
    type Item = u8;
    type Buffer = VecBuffer<u8>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _: &mut TaskContext<'_>,
        _: StoreContextMut<'a, State>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        _: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        let stream = self.get_mut();
        let items = mem::take(&mut stream.items);
        stream
            .stats
            .lock()
            .expect("CLI stdin stats mutex poisoned")
            .items
            .extend_from_slice(&items);
        destination.set_buffer(items.into());
        Poll::Ready(Ok(StreamResult::Dropped))
    }
}

struct RecordingCompletion {
    stats: Arc<Mutex<Stats>>,
    pending: bool,
}

impl Drop for RecordingCompletion {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("CLI stdin stats mutex poisoned")
            .future_dropped = true;
    }
}

impl Future for RecordingCompletion {
    type Output = wasmtime::Result<std::result::Result<(), wasi::cli::types::ErrorCode>>;

    fn poll(self: Pin<&mut Self>, _: &mut TaskContext<'_>) -> Poll<Self::Output> {
        self.stats
            .lock()
            .expect("CLI stdin stats mutex poisoned")
            .completion_polls += 1;
        if self.pending {
            Poll::Pending
        } else {
            Poll::Ready(Ok(Ok(())))
        }
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

#[cfg(unix)]
fn read_local_pipe() -> Result<Vec<u8>> {
    let (mut reader, mut writer) = UnixStream::pair().context("create local CLI stdin pipe")?;
    let payload = vec![100, 50];
    let writer_thread = thread::spawn(move || -> Result<()> {
        writer
            .write_all(&payload)
            .context("write local CLI stdin pipe")?;
        writer
            .shutdown(std::net::Shutdown::Write)
            .context("close local CLI stdin pipe")?;
        Ok(())
    });
    let mut items = Vec::new();
    reader
        .read_to_end(&mut items)
        .context("read local CLI stdin pipe")?;
    writer_thread
        .join()
        .map_err(|_| anyhow::anyhow!("local CLI stdin pipe writer panicked"))??;
    Ok(items)
}

#[cfg(not(unix))]
fn read_local_pipe() -> Result<Vec<u8>> {
    bail!("D2 local CLI stdin pipe requires a Unix host")
}

fn install_stdin_provider(
    linker: &mut Linker<State>,
    stats: Arc<Mutex<Stats>>,
    completion_pending: bool,
    items: Vec<u8>,
) -> wasmtime::Result<()> {
    _ = linker.instance(CLI_TYPES_INSTANCE)?;
    let mut stdin = linker.instance(CLI_STDIN_INSTANCE)?;
    stdin.func_wrap("read-via-stream", move |mut store, ()| {
        stats
            .lock()
            .expect("CLI stdin stats mutex poisoned")
            .provider_calls += 1;
        let stream_stats = Arc::clone(&stats);
        let completion_stats = Arc::clone(&stats);
        let stream_items = items.clone();
        let reader = StreamReader::new(
            &mut store,
            RecordingStream {
                stats: stream_stats,
                items: stream_items,
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            RecordingCompletion {
                stats: completion_stats,
                pending: completion_pending,
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-cli-stream-stdin-host-runner <component.wasm>")?;
    let completion_pending = std::env::var_os("DO_STREAM_COMPLETION_READY").is_none();
    let scheduler_limit = std::env::var("DO_CLI_STDIN_SCHEDULER_LIMIT")
        .ok()
        .map(|value| {
            value
                .parse::<u64>()
                .context("invalid CLI stdin scheduler limit")
        })
        .transpose()?;
    let budget_limit = std::env::var("DO_CLI_STDIN_BUDGET_LIMIT")
        .ok()
        .map(|value| {
            value
                .parse::<i64>()
                .context("invalid CLI stdin budget limit")
        })
        .transpose()?;
    let expect_budget_rejection = std::env::var_os("DO_CLI_STDIN_BUDGET_EXPECT_REJECT").is_some();
    futures::executor::block_on(run(
        Path::new(&component_path),
        completion_pending,
        scheduler_limit,
        budget_limit,
        expect_budget_rejection,
    ))
}

async fn run(
    component_path: &Path,
    completion_pending: bool,
    scheduler_limit: Option<u64>,
    budget_limit: Option<i64>,
    expect_budget_rejection: bool,
) -> Result<()> {
    let items = if std::env::var_os("DO_D2_CLI_STDIN_PIPE").is_some() {
        read_local_pipe()?
    } else {
        vec![0x61, 0x62]
    };
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
    map_wasmtime(install_stdin_provider(
        &mut linker,
        Arc::clone(&stats),
        completion_pending,
        items.clone(),
    ))?;

    let mut store = Store::new(&engine, State);
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, "run"))?;

    if let Some(limit) = budget_limit {
        let configure = map_wasmtime(
            instance.get_typed_func::<(i64,), (i32,)>(&mut store, "byte-budget-limit"),
        )?;
        let configured = map_wasmtime(configure.call_async(&mut store, (limit,)).await)?;
        if configured.0 != 1 {
            bail!("CLI stdin budget configuration rejected limit={limit}");
        }
        let outcome = store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await;
        if expect_budget_rejection {
            match outcome {
                Ok(Ok(())) => bail!(
                    "CLI stdin budget unexpectedly admitted frame={CLI_STDIN_FRAME_BYTES} limit={limit}"
                ),
                Ok(Err(_)) | Err(_) => {
                    let provider_calls = stats
                        .lock()
                        .expect("CLI stdin stats mutex poisoned")
                        .provider_calls;
                    if provider_calls != 0 {
                        bail!(
                            "CLI stdin budget rejection reached provider limit={limit} provider-calls={provider_calls}"
                        );
                    }
                    println!(
                        "Rust CLI stdin budget adapter rejected limit={limit} frame={CLI_STDIN_FRAME_BYTES} provider-call-count=0"
                    );
                    return Ok(());
                }
            }
        }
        map_wasmtime(map_wasmtime(outcome)?)?;
        let provider_calls = stats
            .lock()
            .expect("CLI stdin stats mutex poisoned")
            .provider_calls;
        if provider_calls != 1 {
            bail!("expected one budgeted CLI stdin provider call, got {provider_calls}");
        }
        println!(
            "Rust CLI stdin budget adapter passed limit={limit} configured=1 frame={CLI_STDIN_FRAME_BYTES} provider-call-count=1"
        );
        return Ok(());
    }

    if let Some(limit) = scheduler_limit {
        let gate = budget_gate::BudgetGate::new(limit);
        let Some(first) = gate.try_acquire(CLI_STDIN_FRAME_BYTES) else {
            let provider_calls = stats
                .lock()
                .expect("CLI stdin stats mutex poisoned")
                .provider_calls;
            println!(
                "Rust CLI stdin scheduler rejected before call limit={limit} frame={CLI_STDIN_FRAME_BYTES} provider-call-count={provider_calls}"
            );
            return Ok(());
        };
        if gate.try_acquire(CLI_STDIN_FRAME_BYTES).is_some() {
            bail!(
                "CLI stdin scheduler admitted a second frame before the first completed limit={limit}"
            );
        }
        map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
                .await,
        )?)?;
        if gate.used() != CLI_STDIN_FRAME_BYTES {
            bail!("CLI stdin scheduler permit released before first completion");
        }
        drop(first);
        if gate.used() != 0 {
            bail!("CLI stdin scheduler permit was not released after first completion");
        }
        let second = gate
            .try_acquire(CLI_STDIN_FRAME_BYTES)
            .ok_or_else(|| anyhow::anyhow!("CLI stdin scheduler did not admit released frame"))?;
        map_wasmtime(map_wasmtime(
            store
                .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
                .await,
        )?)?;
        drop(second);
        if gate.used() != 0 {
            bail!("CLI stdin scheduler permit was not released after second completion");
        }
        let stats = stats.lock().expect("CLI stdin stats mutex poisoned");
        if stats.provider_calls != 2 || stats.items != [0x61, 0x62, 0x61, 0x62] {
            bail!(
                "expected two admitted stdin calls and bytes [97, 98, 97, 98]; got provider-calls={}, items={:?}",
                stats.provider_calls,
                stats.items,
            );
        }
        println!(
            "Rust CLI stdin scheduler admission passed limit={limit} rejected=1 released=1 provider-call-count={} items={:?}",
            stats.provider_calls, stats.items,
        );
        return Ok(());
    }

    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    map_wasmtime(call)?;

    let stats = stats.lock().expect("CLI stdin stats mutex poisoned");
    if stats.items != items
        || stats.provider_calls != 1
        || stats.completion_polls != 0
        || !stats.stream_dropped
        || !stats.future_dropped
    {
        bail!(
            "expected one provider call, guest bytes [97, 98], unread completion drop, and both handles dropped; got provider-calls={}, items={:?}, completion-polls={}, stream-dropped={}, future-dropped={}",
            stats.provider_calls,
            stats.items,
            stats.completion_polls,
            stats.stream_dropped,
            stats.future_dropped,
        );
    }

    println!(
        "Rust CLI stdin stream execution passed items={:?} eof=true completion-unread-dropped=true stream-dropped=true future-dropped=true",
        stats.items
    );
    Ok(())
}
