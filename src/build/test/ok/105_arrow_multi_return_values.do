pair() -> i32, bool => 1, true

test "arrow multi return values" {
    n, ok = pair()
    if ok return
    consume(n)
}
