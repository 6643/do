.host_tcp_bind = @host("wasi:sockets/types@0.3.0", "tcp-socket.bind", (TcpSocket, IpSocketAddress) -> Result<nil, TcpError>)
.host_udp_bind = @host("wasi:sockets/types@0.3.0", "udp-socket.bind", (UdpSocket, IpSocketAddress) -> Result<nil, UdpError>)
TcpSocket = @wasi_resource("sockets/types/tcp-socket", {
    .id i64
})
UdpSocket = @wasi_resource("sockets/types/udp-socket", {
    .id i64
})
Ipv4SocketAddress {
    .a u8
    .b u8
    .c u8
    .d u8
    .port u16
}
IpSocketAddress = V4(Ipv4SocketAddress)
TcpError error = TcpClosed | TcpHostFailure
UdpError error = UdpClosed | UdpHostFailure

start() {
    tcp TcpSocket = TcpSocket{id = 1}
    udp UdpSocket = UdpSocket{id = 2}
    address Ipv4SocketAddress = Ipv4SocketAddress{a = 127, b = 0, c = 0, d = 1, port = 8080}
    total IpSocketAddress = V4(address)
    tcp_bound Result<nil, TcpError> = host_tcp_bind(tcp, total)
    if @is(tcp_bound, Err) {
        tcp_failure TcpError = tcp_bound
    }
    udp_bound Result<nil, UdpError> = host_udp_bind(udp, total)
    if @is(udp_bound, Err) {
        udp_failure UdpError = udp_bound
    }
}
