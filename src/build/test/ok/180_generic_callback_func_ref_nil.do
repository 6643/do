tap = @lib("fp.do", tap)

noop(x i32) -> nil {
    _ = x
    return
}

test "generic callback function ref nil return" {
    value i32 = tap(7, noop)
    if @eq(value, 7) return
}
