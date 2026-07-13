// Network address values (scheme B + legacy flat SocketAddr).
// Value semantics only: no pointers/refs.

SocketAddr {
    .family u8
    .ip0 u64
    .ip1 u64
    .port u16
}

socket_addr_v4(a u8, b u8, c u8, d u8, port_value u16) -> SocketAddr {
    ip u32 = @add(@mul(@as(u32, a), 16777216), @mul(@as(u32, b), 65536), @mul(@as(u32, c), 256), @as(u32, d))
    return SocketAddr{family = 4, ip0 = @as(u64, ip), ip1 = 0, port = port_value}
}

socket_addr_v6(hi u64, lo u64, port_value u16) -> SocketAddr {
    return SocketAddr{family = 6, ip0 = hi, ip1 = lo, port = port_value}
}

family(addr SocketAddr) -> u8 {
    return @get(addr, .family)
}

ip0(addr SocketAddr) -> u64 {
    return @get(addr, .ip0)
}

ip1(addr SocketAddr) -> u64 {
    return @get(addr, .ip1)
}

port(addr SocketAddr) -> u16 {
    return @get(addr, .port)
}

is_v4(addr SocketAddr) -> bool {
    return @eq(family(addr), 4)
}

is_v6(addr SocketAddr) -> bool {
    return @eq(family(addr), 6)
}

// G6.3 scheme B: dual concrete address + payload enum total type.

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

ipv4_socket_address(a u8, b u8, c u8, d u8, port_value u16) -> Ipv4SocketAddress {
    return Ipv4SocketAddress{a = a, b = b, c = c, d = d, port = port_value}
}

ipv6_socket_address(hi u64, lo u64, port_value u16) -> Ipv6SocketAddress {
    return Ipv6SocketAddress{hi = hi, lo = lo, port = port_value}
}

ip_socket_address_v4(a u8, b u8, c u8, d u8, port_value u16) -> IpSocketAddress {
    v Ipv4SocketAddress = ipv4_socket_address(a, b, c, d, port_value)
    return V4(v)
}

ip_socket_address_v6(hi u64, lo u64, port_value u16) -> IpSocketAddress {
    v Ipv6SocketAddress = ipv6_socket_address(hi, lo, port_value)
    return V6(v)
}
