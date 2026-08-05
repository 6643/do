use anyhow::{Context, Result, bail};
use std::future::Future;
use std::mem;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{
    Component, Destination, FutureReader, Linker, StreamProducer, StreamReader, StreamResult,
    VecBuffer,
};
use wasmtime::{Config, Engine, Store, StoreContextMut};

const SOURCE_INSTANCE: &str = "do:stream-probe/source@0.1.0";

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
    #[component(name = "illegal-byte-sequence")]
    IllegalByteSequence,
    #[component(name = "pipe")]
    Pipe,
}

#[derive(Default)]
struct Stats {
    items: Vec<u8>,
    completion_polls: u32,
    stream_drops: u32,
    future_drops: u32,
}

struct RecordingStream {
    stats: Arc<Mutex<Stats>>,
    items: Vec<u8>,
}

impl Drop for RecordingStream {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("stream probe stats mutex poisoned")
            .stream_drops += 1;
    }
}

impl StreamProducer<()> for RecordingStream {
    type Item = u8;
    type Buffer = VecBuffer<u8>;

    fn poll_produce<'a>(
        self: Pin<&mut Self>,
        _: &mut TaskContext<'_>,
        _: StoreContextMut<'a, ()>,
        mut destination: Destination<'a, Self::Item, Self::Buffer>,
        _: bool,
    ) -> Poll<wasmtime::Result<StreamResult>> {
        let stream = self.get_mut();
        let items = mem::take(&mut stream.items);
        stream
            .stats
            .lock()
            .expect("stream probe stats mutex poisoned")
            .items
            .extend_from_slice(&items);
        destination.set_buffer(items.into());
        Poll::Ready(Ok(StreamResult::Dropped))
    }
}

struct RecordingCompletion {
    stats: Arc<Mutex<Stats>>,
}

impl Drop for RecordingCompletion {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("stream probe stats mutex poisoned")
            .future_drops += 1;
    }
}

impl Future for RecordingCompletion {
    type Output = wasmtime::Result<std::result::Result<(), ErrorCode>>;

    fn poll(self: Pin<&mut Self>, _: &mut TaskContext<'_>) -> Poll<Self::Output> {
        self.stats
            .lock()
            .expect("stream probe stats mutex poisoned")
            .completion_polls += 1;
        Poll::Pending
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn install_source(linker: &mut Linker<()>, stats: Arc<Mutex<Stats>>) -> wasmtime::Result<()> {
    let mut source = linker.instance(SOURCE_INSTANCE)?;
    source.func_wrap("read-via-stream", move |mut store, ()| {
        let reader = StreamReader::new(
            &mut store,
            RecordingStream {
                stats: Arc::clone(&stats),
                items: vec![0x61, 0x62],
            },
        )?;
        let completion = FutureReader::new(
            &mut store,
            RecordingCompletion {
                stats: Arc::clone(&stats),
            },
        )?;
        Ok(((reader, completion),))
    })?;
    Ok(())
}

fn main() -> Result<()> {
    let component_path = std::env::args()
        .nth(1)
        .context("usage: do-p3-stream-reader-host-runner <component.wasm>")?;
    futures::executor::block_on(run(Path::new(&component_path)))
}

async fn run(component_path: &Path) -> Result<()> {
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
    map_wasmtime(install_source(&mut linker, Arc::clone(&stats)))?;

    let mut store = Store::new(&engine, ());
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let run = map_wasmtime(instance.get_typed_func::<(), ()>(&mut store, "run"))?;
    let call = map_wasmtime(
        store
            .run_concurrent(async |accessor| run.call_concurrent(&accessor, ()).await)
            .await,
    )?;
    map_wasmtime(call)?;

    let stats = stats.lock().expect("stream probe stats mutex poisoned");
    if stats.items != [0x61, 0x62]
        || stats.completion_polls != 0
        || stats.stream_drops != 1
        || stats.future_drops != 1
    {
        bail!(
            "expected stream items [97, 98], EOF, no completion poll, and one drop each; got items={:?}, completion-polls={}, stream-drops={}, future-drops={}",
            stats.items,
            stats.completion_polls,
            stats.stream_drops,
            stats.future_drops,
        );
    }

    println!(
        "Rust custom stream reader execution passed items=[97, 98] eof=true completion-unread-dropped=true stream-drops=1 future-drops=1"
    );
    Ok(())
}
