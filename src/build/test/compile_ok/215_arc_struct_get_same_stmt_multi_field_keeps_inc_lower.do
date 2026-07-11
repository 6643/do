Pair {
    left [u8]
    right [u8]
}

same(left [u8], right [u8]) -> bool {
    return @eq(left, right)
}

start() {
    left [u8] = "a"
    right [u8] = "b"
    pair Pair = Pair{left = left, right = right}
    ok bool = same(@get(pair, .left), @get(pair, .right))
    return
}
