// TCP sockets — G6.3 scheme B (create/bind/drop). Value handle + explicit close.

.host_tcp_create = @host_func("wasi:sockets/types@0.3.0", "tcp-socket.create", (u8) -> TcpSocket | TcpError)
.host_tcp_bind = @host_func("wasi:sockets/types@0.3.0", "tcp-socket.bind", (TcpSocket, IpSocketAddress) -> nil | TcpError)
.host_tcp_drop = @host_func("wasi:sockets/types@0.3.0", "tcp-socket.drop", (TcpSocket) -> nil)

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

TcpSocket = @wasi_resource("sockets/types/tcp-socket", {
    .id i64
})

TcpError error = TcpClosed | TcpUnsupportedAddress | TcpHostFailure

ipv4_socket_address(a u8, b u8, c u8, d u8, port_value u16) -> Ipv4SocketAddress {
    return Ipv4SocketAddress{a = a, b = b, c = c, d = d, port = port_value}
}

ipv6_socket_address(hi u64, lo u64, port_value u16) -> Ipv6SocketAddress {
    return Ipv6SocketAddress{hi = hi, lo = lo, port = port_value}
}

// Family: public wrappers use 4=ipv4 and 6=ipv6; codegen maps to WIT 0/1.
create_tcp_v4() -> TcpSocket | TcpError {
    result TcpSocket | TcpError = host_tcp_create(4)
    if @is(result, TcpError) return result
    socket TcpSocket = result
    return socket
}

create_tcp_v6() -> TcpSocket | TcpError {
    result TcpSocket | TcpError = host_tcp_create(6)
    if @is(result, TcpError) return result
    socket TcpSocket = result
    return socket
}

// Public bind overloads: concrete address types. Intermediate total local is
// supported under @lib after imported payload-enum collect (G6.3 edge fix).
bind_tcp(sock TcpSocket, addr Ipv4SocketAddress) -> TcpError | nil {
    total IpSocketAddress = V4(addr)
    result nil | TcpError = host_tcp_bind(sock, total)
    if @is(result, TcpError) return result
    return nil
}

bind_tcp(sock TcpSocket, addr Ipv6SocketAddress) -> TcpError | nil {
    total IpSocketAddress = V6(addr)
    result nil | TcpError = host_tcp_bind(sock, total)
    if @is(result, TcpError) return result
    return nil
}

// Explicit names for callers that prefer non-overload aliases.
bind_tcp_v4(sock TcpSocket, addr Ipv4SocketAddress) -> TcpError | nil {
    total IpSocketAddress = V4(addr)
    result nil | TcpError = host_tcp_bind(sock, total)
    if @is(result, TcpError) return result
    return nil
}

bind_tcp_v6(sock TcpSocket, addr Ipv6SocketAddress) -> TcpError | nil {
    total IpSocketAddress = V6(addr)
    result nil | TcpError = host_tcp_bind(sock, total)
    if @is(result, TcpError) return result
    return nil
}

close_tcp(sock TcpSocket) -> nil {
    host_tcp_drop(sock)
    return
}

is_tcp_closed(err TcpError) -> bool {
    return @eq(err, TcpClosed)
}
