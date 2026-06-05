pick(rest ...i32) -> bool {
    return true
}

pick(rest ...i32) -> i32 {
    return 1
}

test "variadic duplicate signature return" {
    x = pick(1)
    return
}
