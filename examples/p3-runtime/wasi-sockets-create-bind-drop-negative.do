// Negative private D2 target source: connect is outside the admitted slice.
.host_tcp_create = @host("wasi:sockets/types@0.3.0", "tcp-socket.create", (u8) -> TcpSocket | TcpError)
.host_tcp_bind = @host("wasi:sockets/types@0.3.0", "tcp-socket.bind", (TcpSocket, IpSocketAddress) -> TcpError | nil)
.host_tcp_drop = @host("wasi:sockets/types@0.3.0", "tcp-socket.drop", (TcpSocket) -> nil)
.host_tcp_connect = @host("wasi:sockets/types@0.3.0", "tcp-socket.connect", (TcpSocket, IpSocketAddress) -> TcpError | nil)

TcpSocket = @wasi_resource("sockets/types/tcp-socket", {
    .id i64
})

TcpError error = TcpClosed | TcpUnsupportedAddress | TcpHostFailure

Ipv4SocketAddress {
    .a u8
    .b u8
    .c u8
    .d u8
    .port u16
}

IpSocketAddress = V4(Ipv4SocketAddress)

run() -> u32 {
    socket TcpSocket | TcpError = host_tcp_create(4)
    if @is(socket, TcpError) return 0
    tcp TcpSocket = socket
    address Ipv4SocketAddress = Ipv4SocketAddress{a = 127, b = 0, c = 0, d = 1, port = 0}
    connected TcpError | nil = host_tcp_connect(tcp, V4(address))
    _ = connected
    host_tcp_drop(tcp)
    return 1
}
