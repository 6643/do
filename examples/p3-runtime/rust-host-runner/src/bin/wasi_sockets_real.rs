use anyhow::{Context, Result, bail};
use std::net::{Ipv4Addr, TcpListener, UdpSocket};
use std::path::Path;
use wasmtime::component::{Component, HasSelf, Linker, Resource, ResourceTable};
use wasmtime::{Config, Engine, Store};

pub enum TcpSocket {
    Unbound,
    Bound(TcpListener),
}

pub enum UdpSocketResource {
    Unbound,
    Bound(UdpSocket),
}

wasmtime::component::bindgen!({
    path: "../wit/wasi-sockets-create-bind-drop.wit",
    world: "socket-probe",
    with: {
        "wasi:sockets/types.tcp-socket": TcpSocket,
        "wasi:sockets/types.udp-socket": UdpSocketResource,
    },
});

#[derive(Clone, Copy, PartialEq, Eq)]
enum Failure {
    None,
    Create,
    Bind,
}

#[derive(Default)]
struct Stats {
    create: u32,
    bind: u32,
    drop: u32,
    errors: u32,
}

struct State {
    table: ResourceTable,
    stats: Stats,
    failure: Failure,
}

fn trace(message: impl std::fmt::Display) {
    if std::env::var_os("DO_D2_SOCKET_TRACE").is_some() {
        eprintln!("[socket-trace] {message}");
    }
}

impl wasi::sockets::types::Host for State {}

impl wasi::sockets::types::HostTcpSocket for State {
    fn create(
        &mut self,
        family: wasi::sockets::types::IpAddressFamily,
    ) -> Result<Resource<TcpSocket>, wasi::sockets::types::ErrorCode> {
        self.stats.create += 1;
        trace(format!(
            "tcp.create family={family:?} before-table-empty={}",
            self.table.is_empty()
        ));
        if self.failure == Failure::Create || family != wasi::sockets::types::IpAddressFamily::Ipv4
        {
            self.stats.errors += 1;
            trace("tcp.create -> error");
            return Err(wasi::sockets::types::ErrorCode::HostFailure);
        }
        let result = self.table.push(TcpSocket::Unbound).map_err(|_| {
            self.stats.errors += 1;
            wasi::sockets::types::ErrorCode::HostFailure
        });
        trace(format!(
            "tcp.create -> {result:?} after-table-empty={}",
            self.table.is_empty()
        ));
        result
    }

    fn bind(
        &mut self,
        socket: Resource<TcpSocket>,
        address: wasi::sockets::types::IpSocketAddress,
    ) -> Result<(), wasi::sockets::types::ErrorCode> {
        self.stats.bind += 1;
        trace(format!(
            "tcp.bind socket={socket:?} address={address:?} table-empty={}",
            self.table.is_empty()
        ));
        if self.failure == Failure::Bind {
            self.stats.errors += 1;
            trace("tcp.bind -> error");
            return Err(wasi::sockets::types::ErrorCode::HostFailure);
        }
        let port = match address {
            wasi::sockets::types::IpSocketAddress::Ipv4(value) => value.port,
            wasi::sockets::types::IpSocketAddress::Ipv6(_) => {
                self.stats.errors += 1;
                trace("tcp.bind -> unsupported address");
                return Err(wasi::sockets::types::ErrorCode::UnsupportedAddress);
            }
        };
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, port)).map_err(|_| {
            self.stats.errors += 1;
            wasi::sockets::types::ErrorCode::HostFailure
        })?;
        let value = self.table.get_mut(&socket).map_err(|_| {
            self.stats.errors += 1;
            wasi::sockets::types::ErrorCode::Closed
        })?;
        match value {
            TcpSocket::Unbound => {
                *value = TcpSocket::Bound(listener);
                trace("tcp.bind -> ok");
                Ok(())
            }
            TcpSocket::Bound(_) => {
                self.stats.errors += 1;
                trace("tcp.bind -> closed");
                Err(wasi::sockets::types::ErrorCode::Closed)
            }
        }
    }

    fn drop(&mut self, socket: Resource<TcpSocket>) -> wasmtime::Result<()> {
        trace(format!(
            "tcp.drop socket={socket:?} table-empty-before={}",
            self.table.is_empty()
        ));
        self.table.delete(socket)?;
        self.stats.drop += 1;
        trace(format!(
            "tcp.drop -> ok table-empty-after={}",
            self.table.is_empty()
        ));
        Ok(())
    }
}

impl wasi::sockets::types::HostUdpSocket for State {
    fn create(
        &mut self,
        family: wasi::sockets::types::IpAddressFamily,
    ) -> Result<Resource<UdpSocketResource>, wasi::sockets::types::ErrorCode> {
        self.stats.create += 1;
        trace(format!(
            "udp.create family={family:?} before-table-empty={}",
            self.table.is_empty()
        ));
        if self.failure == Failure::Create || family != wasi::sockets::types::IpAddressFamily::Ipv4
        {
            self.stats.errors += 1;
            trace("udp.create -> error");
            return Err(wasi::sockets::types::ErrorCode::HostFailure);
        }
        let result = self.table.push(UdpSocketResource::Unbound).map_err(|_| {
            self.stats.errors += 1;
            wasi::sockets::types::ErrorCode::HostFailure
        });
        trace(format!(
            "udp.create -> {result:?} after-table-empty={}",
            self.table.is_empty()
        ));
        result
    }

    fn bind(
        &mut self,
        socket: Resource<UdpSocketResource>,
        address: wasi::sockets::types::IpSocketAddress,
    ) -> Result<(), wasi::sockets::types::ErrorCode> {
        self.stats.bind += 1;
        trace(format!(
            "udp.bind socket={socket:?} address={address:?} table-empty={}",
            self.table.is_empty()
        ));
        if self.failure == Failure::Bind {
            self.stats.errors += 1;
            trace("udp.bind -> error");
            return Err(wasi::sockets::types::ErrorCode::HostFailure);
        }
        let port = match address {
            wasi::sockets::types::IpSocketAddress::Ipv4(value) => value.port,
            wasi::sockets::types::IpSocketAddress::Ipv6(_) => {
                self.stats.errors += 1;
                trace("udp.bind -> unsupported address");
                return Err(wasi::sockets::types::ErrorCode::UnsupportedAddress);
            }
        };
        let socket_value = UdpSocket::bind((Ipv4Addr::LOCALHOST, port)).map_err(|_| {
            self.stats.errors += 1;
            wasi::sockets::types::ErrorCode::HostFailure
        })?;
        let value = self.table.get_mut(&socket).map_err(|_| {
            self.stats.errors += 1;
            wasi::sockets::types::ErrorCode::Closed
        })?;
        match value {
            UdpSocketResource::Unbound => {
                *value = UdpSocketResource::Bound(socket_value);
                trace("udp.bind -> ok");
                Ok(())
            }
            UdpSocketResource::Bound(_) => {
                self.stats.errors += 1;
                trace("udp.bind -> closed");
                Err(wasi::sockets::types::ErrorCode::Closed)
            }
        }
    }

    fn drop(&mut self, socket: Resource<UdpSocketResource>) -> wasmtime::Result<()> {
        trace(format!(
            "udp.drop socket={socket:?} table-empty-before={}",
            self.table.is_empty()
        ));
        self.table.delete(socket)?;
        self.stats.drop += 1;
        trace(format!(
            "udp.drop -> ok table-empty-after={}",
            self.table.is_empty()
        ));
        Ok(())
    }
}

fn map_wasmtime<T>(result: wasmtime::Result<T>) -> Result<T> {
    result.map_err(|error| anyhow::anyhow!("{error:?}"))
}

fn parse_failure() -> Result<Failure> {
    match std::env::var("DO_D2_SOCKET_FAILURE").as_deref() {
        Ok("none") | Err(std::env::VarError::NotPresent) => Ok(Failure::None),
        Ok("create") => Ok(Failure::Create),
        Ok("bind") => Ok(Failure::Bind),
        Ok(value) => bail!("unsupported DO_D2_SOCKET_FAILURE={value}"),
        Err(error) => bail!("read DO_D2_SOCKET_FAILURE: {error}"),
    }
}

fn run(component_path: &Path, protocol: &str, failure: Failure) -> Result<()> {
    let mut config = Config::new();
    config.wasm_component_model(true);
    let engine = map_wasmtime(Engine::new(&config))?;
    let component = map_wasmtime(Component::from_file(&engine, component_path))?;
    let mut linker: Linker<State> = Linker::new(&engine);
    map_wasmtime(
        wasi::sockets::types::add_to_linker::<State, HasSelf<State>>(&mut linker, |state| state),
    )?;
    let mut store = Store::new(
        &engine,
        State {
            table: ResourceTable::new(),
            stats: Stats::default(),
            failure,
        },
    );
    let instance = map_wasmtime(linker.instantiate(&mut store, &component))?;
    let run = map_wasmtime(instance.get_typed_func::<(), (u32,)>(&mut store, "run"))?;
    let (result,) = map_wasmtime(run.call(&mut store, ()))?;
    let stats = &store.data().stats;
    let expected_result = match failure {
        Failure::None => 1,
        Failure::Create => 0,
        Failure::Bind => 2,
    };
    let expected_bind = if failure == Failure::Create { 0 } else { 1 };
    let expected_drop = if failure == Failure::Create { 0 } else { 1 };
    let expected_errors = if failure == Failure::None { 0 } else { 1 };
    if result != expected_result
        || stats.create != 1
        || stats.bind != expected_bind
        || stats.drop != expected_drop
        || stats.errors != expected_errors
        || !store.data().table.is_empty()
    {
        bail!(
            "unexpected real socket stats: protocol={protocol} result={result} create={} bind={} drop={} errors={} table-empty={}",
            stats.create,
            stats.bind,
            stats.drop,
            stats.errors,
            store.data().table.is_empty(),
        );
    }
    println!(
        "real-sockets passed protocol={protocol} failure={} result={result} create={} bind={} drop={} errors={} table-empty=true",
        match failure {
            Failure::None => "none",
            Failure::Create => "create",
            Failure::Bind => "bind",
        },
        stats.create,
        stats.bind,
        stats.drop,
        stats.errors,
    );
    Ok(())
}

fn main() -> Result<()> {
    let component = std::env::args()
        .nth(1)
        .context("usage: do-p3-wasi-sockets-real <component.wasm> <tcp|udp>")?;
    let protocol = std::env::args()
        .nth(2)
        .context("usage: do-p3-wasi-sockets-real <component.wasm> <tcp|udp>")?;
    if protocol != "tcp" && protocol != "udp" {
        bail!("unsupported protocol {protocol}");
    }
    run(Path::new(&component), &protocol, parse_failure()?)
}
