#F = (i32) -> i32
apply(f F) -> i32 {
    return f(1)
}

twice(f F) -> i32 {
    return f(f(1))
}

test "constraint block not shared" {
    out = twice((x i32) -> i32 => @add(x, 1))
    return
}
