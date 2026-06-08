pair = @lib("~/test.multi_return_pair.do", pair)

forward(x i32) -> i32, bool {
    return pair(x)
}

start() {
    n i32 = 0
    ok bool = false
    n, ok = forward(11)
    return
}
