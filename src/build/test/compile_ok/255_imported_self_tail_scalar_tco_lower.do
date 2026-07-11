sum_tail = @lib("~/test.self_tail_scalar.do", sum_tail)

start() {
    out i32 = sum_tail(5, 0)
    return
}
