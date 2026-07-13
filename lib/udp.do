// UDP sockets — G6.3 scheme B (create/bind/drop). Value handle + explicit close.

.host_udp_create = @wasi_func("sockets/types/udp-socket.create", (u8) -> UdpSocket | UdpError)
.host_udp_bind = @wasi_func("sockets/types/udp-socket.bind", (UdpSocket, IpSocketAddress) -> UdpError | nil)
.host_udp_drop = @wasi_func("sockets/types/udp-socket.drop", (UdpSocket) -> nil)

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

UdpSocket = @wasi_resource("sockets/types/udp-socket", {
    .id i64
})

UdpError error = UdpClosed | UdpUnsupportedAddress | UdpHostFailure

ipv4_socket_address(a u8, b u8, c u8, d u8, port_value u16) -> Ipv4SocketAddress {
    return Ipv4SocketAddress{a = a, b = b, c = c, d = d, port = port_value}
}

ipv6_socket_address(hi u64, lo u64, port_value u16) -> Ipv6SocketAddress {
    return Ipv6SocketAddress{hi = hi, lo = lo, port = port_value}
}

// Family: guest wrappers pass WIT disc 0=ipv4, 1=ipv6.
create_udp_v4() -> UdpSocket | UdpError {
    return host_udp_create(0)
}

create_udp_v6() -> UdpSocket | UdpError {
    return host_udp_create(1)
}

// Public bind overloads: concrete address types. Pack via inline V4/V6 ctor
// (import-safe; same constraint as lib/tcp.do).
bind_udp(sock UdpSocket, addr Ipv4SocketAddress) -> UdpError | nil {
    return host_udp_bind(sock, V4(addr))
}

bind_udp(sock UdpSocket, addr Ipv6SocketAddress) -> UdpError | nil {
    return host_udp_bind(sock, V6(addr))
}

bind_udp_v4(sock UdpSocket, addr Ipv4SocketAddress) -> UdpError | nil {
    return host_udp_bind(sock, V4(addr))
}

bind_udp_v6(sock UdpSocket, addr Ipv6SocketAddress) -> UdpError | nil {
    return host_udp_bind(sock, V6(addr))
}

close_udp(sock UdpSocket) -> nil {
    host_udp_drop(sock)
    return
}

is_udp_closed(err UdpError) -> bool {
    return @eq(err, UdpClosed)
}
