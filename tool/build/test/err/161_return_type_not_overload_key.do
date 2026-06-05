pick(x i32) -> i32 {
    return x
}

pick(x i32) -> bool {
    return gt(x, 0)
}

test "return type not overload key" {
    x = pick(1)
    return
}
