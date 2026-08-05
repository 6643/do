use anyhow::{Context, Result, bail};
use std::future::Future;
use std::path::Path;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context as TaskContext, Poll};
use wasmtime::component::{Component, Linker, Resource, ResourceTable, ResourceType};
use wasmtime::{Config, Engine, Store};

const HTTP_TYPES_INSTANCE: &str = "wasi:http/types@0.3.0-rc-2025-09-16";
const HTTP_CLIENT_INSTANCE: &str = "wasi:http/client@0.3.0-rc-2025-09-16";

pub struct Request;
pub struct Response;

wasmtime::component::bindgen!({
    path: [
        "../../../src/build/p3_wit/wasi-http-0.3.0-rc-2025-09-16",
        "http-payload-cancel-wit/http-payload-cancel-types.wit",
    ],
    world: "do:http-payload-cancel/http-payload-cancel-types@0.1.0",
    imports: { default: async | trappable },
    exports: { default: async },
    with: {
        "wasi:http/types.request": Request,
        "wasi:http/types.response": Response,
    },
});

#[derive(Default)]
struct Stats {
    request_consumed: u32,
    response_created: u32,
    response_dropped: u32,
    pending_polls: u32,
    pending_drops: u32,
    ready_polls: u32,
    ready_drops: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Mode {
    Pending,
    ReadyOk,
    ReadyDnsTimeout,
    ReadyDnsError,
    ReadyDnsErrorLong,
    ReadyInternalError,
    ReadyDnsErrorNone,
    ReadyInternalErrorNone,
}

impl Mode {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "pending" => Ok(Self::Pending),
            "ready-ok" => Ok(Self::ReadyOk),
            "ready-dns-timeout" => Ok(Self::ReadyDnsTimeout),
            "ready-dns-error" => Ok(Self::ReadyDnsError),
            "ready-dns-error-long" => Ok(Self::ReadyDnsErrorLong),
            "ready-internal-error" => Ok(Self::ReadyInternalError),
            "ready-dns-error-none" => Ok(Self::ReadyDnsErrorNone),
            "ready-internal-error-none" => Ok(Self::ReadyInternalErrorNone),
            _ => bail!(
                "unknown HTTP payload cancellation mode {value:?}; expected pending, ready-ok, ready-dns-timeout, ready-dns-error, ready-dns-error-long, ready-internal-error, ready-dns-error-none, or ready-internal-error-none"
            ),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::ReadyOk => "ready-ok",
            Self::ReadyDnsTimeout => "ready-dns-timeout",
            Self::ReadyDnsError => "ready-dns-error",
            Self::ReadyDnsErrorLong => "ready-dns-error-long",
            Self::ReadyInternalError => "ready-internal-error",
            Self::ReadyDnsErrorNone => "ready-dns-error-none",
            Self::ReadyInternalErrorNone => "ready-internal-error-none",
        }
    }
}

struct State {
    table: ResourceTable,
    stats: Stats,
    mode: Mode,
}

struct PendingSend {
    stats: Arc<Mutex<Stats>>,
}

type SendResult = std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>;
type SendOutput = wasmtime::Result<(SendResult,)>;

impl Future for PendingSend {
    type Output = SendOutput;

    fn poll(self: Pin<&mut Self>, _cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        self.stats
            .lock()
            .expect("HTTP cancellation stats mutex poisoned")
            .pending_polls += 1;
        Poll::Pending
    }
}

struct ReadySend {
    stats: Arc<Mutex<Stats>>,
    result: Option<SendResult>,
}

impl Future for ReadySend {
    type Output = SendOutput;

    fn poll(mut self: Pin<&mut Self>, _cx: &mut TaskContext<'_>) -> Poll<Self::Output> {
        self.stats
            .lock()
            .expect("HTTP cancellation stats mutex poisoned")
            .ready_polls += 1;
        Poll::Ready(Ok((self
            .result
            .take()
            .expect("HTTP ready future polled after completion"),)))
    }
}

impl Drop for ReadySend {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("HTTP cancellation stats mutex poisoned")
            .ready_drops += 1;
    }
}

impl Drop for PendingSend {
    fn drop(&mut self) {
        self.stats
            .lock()
            .expect("HTTP cancellation stats mutex poisoned")
            .pending_drops += 1;
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:#}"))
}

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let component_path = args
        .next()
        .context("usage: do-p3-http-payload-cancel-host-runner <component.wasm> <pending|ready-ok|ready-dns-timeout|ready-dns-error|ready-dns-error-long|ready-internal-error|ready-dns-error-none|ready-internal-error-none> [--expect-dns-error-discard|--expect-internal-error-discard] [--twice]")?;
    let mode_name = args
        .next()
        .context("missing HTTP payload cancellation mode")?;
    let mut expectation: Option<String> = None;
    let mut invocation_count = 1;
    for argument in args {
        match argument.as_str() {
            "--expect-dns-error-discard" | "--expect-internal-error-discard" => {
                if expectation.replace(argument).is_some() {
                    bail!("expected at most one HTTP payload cancellation expectation");
                }
            }
            "--twice" => {
                if invocation_count != 1 {
                    bail!("HTTP payload cancellation invocation count is already two");
                }
                invocation_count = 2;
            }
            value => bail!("unknown HTTP payload cancellation argument {value:?}"),
        }
    }
    let expect_payload_error_discard = matches!(
        expectation.as_deref(),
        Some("--expect-dns-error-discard" | "--expect-internal-error-discard")
    );
    let mode = Mode::parse(&mode_name)?;
    match expectation.as_deref() {
        Some("--expect-dns-error-discard")
            if !matches!(
                mode,
                Mode::ReadyDnsError | Mode::ReadyDnsErrorLong | Mode::ReadyDnsErrorNone
            ) =>
        {
            bail!("--expect-dns-error-discard requires a ready DNS-error mode");
        }
        Some("--expect-internal-error-discard")
            if !matches!(
                mode,
                Mode::ReadyInternalError | Mode::ReadyInternalErrorNone
            ) =>
        {
            bail!("--expect-internal-error-discard requires ready-internal-error mode");
        }
        _ => {}
    }
    futures::executor::block_on(run(
        Path::new(&component_path),
        mode,
        expect_payload_error_discard,
        invocation_count,
    ))
}

async fn run(
    component_path: &Path,
    mode: Mode,
    expect_payload_error_discard: bool,
    invocation_count: u32,
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
    let host_stats = Arc::new(Mutex::new(Stats::default()));
    let mut linker: Linker<State> = Linker::new(&engine);
    let mut types = map_wasmtime(linker.instance(HTTP_TYPES_INSTANCE))?;
    map_wasmtime(types.resource(
        "request",
        ResourceType::host::<Request>(),
        |mut store, rep| {
            let state = store.data_mut();
            let _ = state.table.delete(Resource::<Request>::new_own(rep))?;
            Ok(())
        },
    ))?;
    map_wasmtime(types.resource(
        "response",
        ResourceType::host::<Response>(),
        |mut store, rep| {
            let state = store.data_mut();
            let _ = state.table.delete(Resource::<Response>::new_own(rep))?;
            state.stats.response_dropped += 1;
            Ok(())
        },
    ))?;

    let send_stats = Arc::clone(&host_stats);
    let mut client = map_wasmtime(linker.instance(HTTP_CLIENT_INSTANCE))?;
    map_wasmtime(client.func_wrap_concurrent(
        "send",
        move |accessor, (request,): (Resource<Request>,)| {
            let result = accessor.with(|mut access| {
                let state = access.data_mut();
                let _ = state.table.delete(request)?;
                state.stats.request_consumed += 1;
                match state.mode {
                    Mode::Pending => Ok::<
                        Option<
                            std::result::Result<Resource<Response>, wasi::http::types::ErrorCode>,
                        >,
                        wasmtime::Error,
                    >(None),
                    Mode::ReadyOk => {
                        let response = state.table.push(Response)?;
                        state.stats.response_created += 1;
                        Ok(Some(Ok(response)))
                    }
                    Mode::ReadyDnsTimeout => {
                        Ok(Some(Err(wasi::http::types::ErrorCode::DnsTimeout)))
                    }
                    Mode::ReadyDnsError => Ok(Some(Err(wasi::http::types::ErrorCode::DnsError(
                        wasi::http::types::DnsErrorPayload {
                            rcode: Some("EAI".to_owned()),
                            info_code: Some(7),
                        },
                    )))),
                    Mode::ReadyDnsErrorLong => {
                        Ok(Some(Err(wasi::http::types::ErrorCode::DnsError(
                            wasi::http::types::DnsErrorPayload {
                                rcode: Some("dns-error-long".to_owned()),
                                info_code: None,
                            },
                        ))))
                    }
                    Mode::ReadyInternalError => Ok(Some(Err(
                        wasi::http::types::ErrorCode::InternalError(Some("no".to_owned())),
                    ))),
                    Mode::ReadyDnsErrorNone => {
                        Ok(Some(Err(wasi::http::types::ErrorCode::DnsError(
                            wasi::http::types::DnsErrorPayload {
                                rcode: None,
                                info_code: None,
                            },
                        ))))
                    }
                    Mode::ReadyInternalErrorNone => {
                        Ok(Some(Err(wasi::http::types::ErrorCode::InternalError(None))))
                    }
                }
            });
            match result {
                Err(error) => Box::pin(async move { Err(error) }),
                Ok(Some(result)) => Box::pin(ReadySend {
                    stats: Arc::clone(&send_stats),
                    result: Some(result),
                }),
                Ok(None) => Box::pin(PendingSend {
                    stats: Arc::clone(&send_stats),
                }),
            }
        },
    ))?;

    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Stats::default(),
            mode,
        },
    );
    let instance = map_wasmtime(linker.instantiate_async(&mut store, &component).await)?;
    let cancel =
        map_wasmtime(instance.get_typed_func::<(Resource<Request>,), ()>(&mut store, "cancel"))?;
    let expected_trap = matches!(
        mode,
        Mode::ReadyDnsError
            | Mode::ReadyDnsErrorLong
            | Mode::ReadyInternalError
            | Mode::ReadyDnsErrorNone
            | Mode::ReadyInternalErrorNone
    ) && !expect_payload_error_discard;
    for _ in 0..invocation_count {
        let request = store.data_mut().table.push(Request)?;
        let invocation = store
            .run_concurrent(async |accessor| cancel.call_concurrent(accessor, (request,)).await)
            .await;
        let call_result = match invocation {
            Ok(result) => map_wasmtime(result),
            Err(error) => Err(anyhow::anyhow!("{error:#}")),
        };
        match (expected_trap, call_result) {
            (true, Ok(())) => bail!("expected payload-error cancellation to trap"),
            (true, Err(error)) => {
                println!("expected trap=true");
                println!("trap={error:#}");
            }
            (false, Ok(())) => println!("expected trap=false"),
            (false, Err(error)) => return Err(error),
        }
    }

    let host_stats = host_stats
        .lock()
        .expect("HTTP cancellation stats mutex poisoned");
    let stats = &store.data().stats;
    let pending_stats_valid = match mode {
        Mode::Pending => {
            host_stats.pending_polls >= invocation_count
                && host_stats.pending_drops == invocation_count
        }
        Mode::ReadyOk
        | Mode::ReadyDnsTimeout
        | Mode::ReadyDnsError
        | Mode::ReadyDnsErrorLong
        | Mode::ReadyInternalError
        | Mode::ReadyDnsErrorNone
        | Mode::ReadyInternalErrorNone => {
            host_stats.pending_polls == 0 && host_stats.pending_drops == 0
        }
    };
    let ready_stats_valid = match mode {
        Mode::Pending => host_stats.ready_polls == 0 && host_stats.ready_drops == 0,
        Mode::ReadyOk
        | Mode::ReadyDnsTimeout
        | Mode::ReadyDnsError
        | Mode::ReadyDnsErrorLong
        | Mode::ReadyInternalError
        | Mode::ReadyDnsErrorNone
        | Mode::ReadyInternalErrorNone => {
            host_stats.ready_polls == invocation_count && host_stats.ready_drops == invocation_count
        }
    };
    let response_stats_valid = match mode {
        Mode::Pending
        | Mode::ReadyDnsTimeout
        | Mode::ReadyDnsError
        | Mode::ReadyDnsErrorLong
        | Mode::ReadyInternalError
        | Mode::ReadyDnsErrorNone
        | Mode::ReadyInternalErrorNone => {
            stats.response_created == 0 && stats.response_dropped == 0
        }
        Mode::ReadyOk => {
            stats.response_created == invocation_count && stats.response_dropped == invocation_count
        }
    };
    if stats.request_consumed != invocation_count
        || !response_stats_valid
        || !pending_stats_valid
        || !ready_stats_valid
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected HTTP cancellation stats: request-consumed={} response-created={} response-dropped={} pending-polls={} pending-future-drops={} table-empty={}",
            stats.request_consumed,
            stats.response_created,
            stats.response_dropped,
            host_stats.pending_polls,
            host_stats.pending_drops,
            store.data().table.is_empty(),
        );
    }

    println!("Rust P3 HTTP payload cancellation probe passed");
    println!("mode={}", mode.name());
    println!("request consumed={invocation_count}");
    println!("pending polls={}", host_stats.pending_polls);
    println!("pending future drops={}", host_stats.pending_drops);
    println!("ready future polls={}", host_stats.ready_polls);
    println!("ready future drops={}", host_stats.ready_drops);
    println!("response create={}", stats.response_created);
    println!("response drop={}", stats.response_dropped);
    println!("table-empty=true");
    Ok(())
}
