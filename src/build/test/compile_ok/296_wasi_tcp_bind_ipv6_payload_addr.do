// G6.3 regression: IPv6 payload address uses explicit big-endian byte stores.
.host_tcp_bind = @host("wasi:sockets/types@0.3.0", "tcp-socket.bind", (TcpSocket, IpSocketAddress) -> TcpError | nil)
.host_tcp_drop = @host("wasi:sockets/types@0.3.0", "tcp-socket.drop", (TcpSocket) -> nil)
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
    v Ipv6SocketAddress = Ipv6SocketAddress{hi = 72623859790382856, lo = 1230066625199609624, port = 8080}
    e TcpError | nil = host_tcp_bind(s, V6(v))
    _ = e
    host_tcp_drop(s)
    return
}
