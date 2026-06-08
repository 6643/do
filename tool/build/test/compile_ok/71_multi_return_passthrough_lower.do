pair() -> i32, bool {
    return 1, true
}

wrap() -> i32, bool {
    return pair()
}

start() {
    a i32 = 0
    ok bool = false
    a, ok = wrap()
    return
}
