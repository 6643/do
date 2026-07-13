// G6.3 scheme B: tcp-socket.bind with payload-enum IpSocketAddress + drop.
.host_tcp_bind = @wasi_func("sockets/types/tcp-socket.bind", (TcpSocket, IpSocketAddress) -> TcpError | nil)
.host_tcp_drop = @wasi_func("sockets/types/tcp-socket.drop", (TcpSocket) -> nil)
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
Ipv6SocketAddress {
    .hi u64
    .lo u64
    .port u16
}
IpSocketAddress = V4(Ipv4SocketAddress) | V6(Ipv6SocketAddress)

start() {
    s TcpSocket = TcpSocket{id = 1}
    a Ipv4SocketAddress = Ipv4SocketAddress{a = 127, b = 0, c = 0, d = 1, port = 8080}
    e TcpError | nil = host_tcp_bind(s, V4(a))
    _ = e
    host_tcp_drop(s)
    return
}
