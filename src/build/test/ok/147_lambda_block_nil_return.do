tap = @lib("fp.do", tap)

test "lambda block nil return" {
    value i32 = 1
    next = tap(value, (x i32) -> nil {
        _ = @add(x, 1)
        return
    })
    if @eq(next, 1) return
}
