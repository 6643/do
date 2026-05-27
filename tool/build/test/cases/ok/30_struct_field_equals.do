Handle {
    fd i32
}

test "struct field equals" {
    handle = Handle{fd = 0}
    expected i32 = 0
    if eq(get(handle, .fd), expected) return
}
