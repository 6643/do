// UDP sockets — G6.3 scheme B (create/bind/drop). Value handle + explicit close.

.host_udp_create = @host("wasi:sockets/types@0.3.0", "udp-socket.create", (u8) -> UdpSocket | UdpError)
.host_udp_bind = @host("wasi:sockets/types@0.3.0", "udp-socket.bind", (UdpSocket, IpSocketAddress) -> UdpError | nil)
.host_udp_drop = @host("wasi:sockets/types@0.3.0", "udp-socket.drop", (UdpSocket) -> nil)

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

// Family: public wrappers use 4=ipv4 and 6=ipv6; codegen maps to WIT 0/1.
create_udp_v4() -> UdpSocket | UdpError {
    return host_udp_create(4)
}

create_udp_v6() -> UdpSocket | UdpError {
    return host_udp_create(6)
}

// Public bind overloads: concrete address types. Intermediate total local is
// supported under @lib after imported payload-enum collect (G6.3 edge fix).
bind_udp(sock UdpSocket, addr Ipv4SocketAddress) -> UdpError | nil {
    total IpSocketAddress = V4(addr)
    return host_udp_bind(sock, total)
}

bind_udp(sock UdpSocket, addr Ipv6SocketAddress) -> UdpError | nil {
    total IpSocketAddress = V6(addr)
    return host_udp_bind(sock, total)
}

bind_udp_v4(sock UdpSocket, addr Ipv4SocketAddress) -> UdpError | nil {
    total IpSocketAddress = V4(addr)
    return host_udp_bind(sock, total)
}

bind_udp_v6(sock UdpSocket, addr Ipv6SocketAddress) -> UdpError | nil {
    total IpSocketAddress = V6(addr)
    return host_udp_bind(sock, total)
}

close_udp(sock UdpSocket) -> nil {
    host_udp_drop(sock)
    return
}

is_udp_closed(err UdpError) -> bool {
    return @eq(err, UdpClosed)
}
