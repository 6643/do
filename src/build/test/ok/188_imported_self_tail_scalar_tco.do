sum_tail = @lib("./fixture.self_tail_scalar.do", sum_tail)

test "imported self tail scalar tco" {
    out i32 = sum_tail(5, 0)
    if @eq(out, 15) return
}
