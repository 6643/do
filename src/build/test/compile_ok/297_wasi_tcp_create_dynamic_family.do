// G6.3 regression: dynamic u8 family values are normalized before the WIT call.
.host_tcp_create = @host("wasi:sockets/types@0.3.0", "tcp-socket.create", (u8) -> TcpSocket | TcpError)
.host_tcp_drop = @host("wasi:sockets/types@0.3.0", "tcp-socket.drop", (TcpSocket) -> nil)
TcpSocket = @wasi_resource("sockets/types/tcp-socket", {
    .id i64
})
TcpError error = TcpClosed | TcpUnsupportedAddress | TcpHostFailure

make_socket(family u8) -> TcpSocket | TcpError {
    return host_tcp_create(family)
}

start() {
    r TcpSocket | TcpError = make_socket(4)
    _ = r
    return
}
