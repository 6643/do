Packet {
    bytes [u8]
}

rewrite(packet Packet) -> Packet {
    return @set(packet, .bytes, @set(@get(packet, .bytes), 0, 65))
}

start() {}
