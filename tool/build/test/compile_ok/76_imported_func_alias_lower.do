other_pair = @lib("~/test.multi_return_pair.do", pair)

start() {
    n i32 = 0
    ok bool = false
    n, ok = other_pair(9)
    return
}
