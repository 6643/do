sum_tail = @lib("~/test.self_tail_scalar.do", sum_tail)

test "compiled imported self tail scalar tco" {
    out i32 = sum_tail(5, 0)
    if @eq(out, 15) return
}
