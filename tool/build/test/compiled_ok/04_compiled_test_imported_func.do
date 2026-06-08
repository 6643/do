other_pair = @lib("~/test.multi_return_pair.do", pair)

test "compiled imported func" {
    n i32 = 0
    ok bool = false
    n, ok = other_pair(9)
    if @and(@eq(n, 9), ok) return
}
