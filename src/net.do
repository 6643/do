SocketAddr {
    .family u8
    .ip0 u64
    .ip1 u64
    .port u16
}

socket_addr_v4(a u8, b u8, c u8, d u8, port u16) -> SocketAddr {
    ip u32 = add(mul(to_u32(a), 16777216), mul(to_u32(b), 65536), mul(to_u32(c), 256), to_u32(d))
    return SocketAddr{family = 4, ip0 = to_u64(ip), ip1 = 0, port = port}
}

socket_addr_v6(hi u64, lo u64, port u16) -> SocketAddr {
    return SocketAddr{family = 6, ip0 = hi, ip1 = lo, port = port}
}

family(addr SocketAddr) -> u8 {
    return get(addr, .family)
}

ip0(addr SocketAddr) -> u64 {
    return get(addr, .ip0)
}

ip1(addr SocketAddr) -> u64 {
    return get(addr, .ip1)
}

port(addr SocketAddr) -> u16 {
    return get(addr, .port)
}

is_v4(addr SocketAddr) -> bool {
    return eq(family(addr), 4)
}

is_v6(addr SocketAddr) -> bool {
    return eq(family(addr), 6)
}
