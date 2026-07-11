pick(x i32) -> i32 {
    return 1
}

pick(rest ...i32) -> i32 {
    return 2
}

test "fixed overload beats variadic" {
    x = pick(1)
    if @eq(x, 1) return
}
