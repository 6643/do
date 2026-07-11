pair = @lib("~/test.multi_return_pair.do", pair)

start() {
    n i32 = 0
    ok bool = false
    n, ok = pair(7)
    return
}
