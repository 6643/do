.host_tcp_create = @host("wasi:sockets/types@0.3.0", "tcp-socket.create", (u8) -> Result<TcpSocket, TcpError>)
TcpSocket = @wasi_resource("sockets/types/tcp-socket", {
    .id i64
})
TcpError error = TcpClosed | TcpHostFailure

start() {
    created Result<TcpSocket, TcpError> = host_tcp_create(4)
    if @is(created, Ok) {
        socket TcpSocket = created
    }
}
