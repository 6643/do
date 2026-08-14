Message = Empty | Bytes([u8])

rewrite(value Message, bytes [u8]) -> Message {
    return Bytes(bytes)
}

start() {}
