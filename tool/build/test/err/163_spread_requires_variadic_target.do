pair(a i32, b i32) -> i32 {
    return @add(a, b)
}

call_pair(xs [i32]) -> i32 {
    return pair(...xs)
}

test "spread requires variadic target" {
    values [i32] = .{1, 2}
    x = call_pair(values)
    return
}
