Handle {
    fd i32
}

test "struct field private init" {
    handle = Handle{.fd = 0}
    return
}
