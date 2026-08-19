Box {
    value [u8]
    tag i32
}

#T
identity(value T) -> T {
    return value
}

relay(box Box, next [u8]) -> Box {
    _ = next
    return identity(box)
}

start() {}

test "compiled generic managed identity preserves value" {
    original [u8] = "abc"
    next [u8] = "def"
    box Box = Box{value = original, tag = 7}
    updated Box = relay(box, next)
    if @and(@eq(@get(updated, .value), original), @eq(@get(updated, .tag), 7)) return
}
