// G6.3 scheme B: tcp-socket.create → TcpSocket | TcpError (resource + coarse err).
.host_tcp_create = @wasi_func("sockets/types/tcp-socket.create", (u8) -> TcpSocket | TcpError)
TcpSocket = @wasi_resource("sockets/types/tcp-socket", {
    .id i64
})
TcpError error = TcpClosed | TcpUnsupportedAddress | TcpHostFailure

start() {
    r TcpSocket | TcpError = host_tcp_create(4)
    _ = r
    return
}
