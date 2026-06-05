CError error = InvalidHandle | CallFailed

call_c(ptr i32) -> i32 | CError {
    if eq(ptr, 0) return InvalidHandle
    return CallFailed
}

test "error type single letter prefix" {
    v = call_c(0)
    if eq(v, InvalidHandle) return
}
