print(message text) -> nil {
    return
}

cleanup() -> nil {
    return
}

start() {
    cond bool = true
    count i32 = if cond {
        print("b == 1")
        1
    } else 2

    deferred i32 = if cond {
        defer cleanup()
        3
    } else 4

    pair Tuple<i32, bool> = if cond .{count, true} else .{deferred, false}
    count = if cond 128
    _ = pair
    return
}
