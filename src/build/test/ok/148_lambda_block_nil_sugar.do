tap = @lib("fp.do", tap)

test "lambda block nil sugar" {
    value i32 = 1
    next = tap(value, (x i32) {
        _ = @add(x, 2)
        return
    })
    if @eq(next, 1) return
}
