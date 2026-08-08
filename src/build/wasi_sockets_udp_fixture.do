.host_udp_create = @host_func("wasi:sockets/types@0.3.0", "udp-socket.create", (u8) -> UdpSocket | UdpError)
.host_udp_bind = @host_func("wasi:sockets/types@0.3.0", "udp-socket.bind", (UdpSocket, IpSocketAddress) -> UdpError | nil)
.host_udp_drop = @host_func("wasi:sockets/types@0.3.0", "udp-socket.drop", (UdpSocket) -> nil)
UdpSocket = @wasi_resource("sockets/types/udp-socket", { .id i64 })
UdpError error = UdpClosed | UdpUnsupportedAddress | UdpHostFailure
Ipv4SocketAddress { .a u8 .b u8 .c u8 .d u8 .port u16 }
IpSocketAddress = V4(Ipv4SocketAddress)
run() -> u32 {
    socket UdpSocket | UdpError = host_udp_create(4)
    if @is(socket, UdpError) return 0
    udp UdpSocket = socket
    address Ipv4SocketAddress = Ipv4SocketAddress{a = 127, b = 0, c = 0, d = 1, port = 0}
    bind_result UdpError | nil = host_udp_bind(udp, V4(address))
    _ = bind_result
    host_udp_drop(udp)
    return 1
}
