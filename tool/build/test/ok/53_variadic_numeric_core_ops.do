sum_many(first i32, second i32, rest ...i32) -> i32 {
    return @add(first, second, ...rest)
}

min_many(first i32, second i32, rest ...i32) -> i32 {
    return @min(first, second, ...rest)
}

max_many(first i32, second i32, rest ...i32) -> i32 {
    return @max(first, second, ...rest)
}

test "variadic numeric core ops" {
    a i32 = @add(1, 2, 3)
    b i32 = @mul(2, 3, 4)
    c i32 = @sub(10, 3, 2)
    d i32 = @div(24, 3, 2)
    e i32 = @rem(29, 5, 2)
    f i32 = sum_many(1, 2, 3)
    g i32 = @min(4, 2, 9)
    h i32 = @max(4, 2, 9)
    i i32 = min_many(4, 2, 9)
    j i32 = max_many(4, 2, 9)
    return
}
