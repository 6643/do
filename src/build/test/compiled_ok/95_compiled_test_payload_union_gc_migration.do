Message = Empty | Bytes([u8])

make(value [u8]) -> Message {
    return Bytes(value)
}

start() {}

test "compiled payload union constructs managed payload" {
    input [u8] = .{1, 2}
    make(input)
    return
}
