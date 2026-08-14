Packet {
    version i32
    bytes [u8]
}

rewrite(packet Packet, next [u8]) -> Packet {
    return @set(packet, .bytes, next)
}

start() {}
