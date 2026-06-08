#T = i32 | i64
#eq(T, T) -> bool
same(a T, b T) -> bool {
    return @eq(a, b)
}

test "func constraint reserved builtin name" {
    a i32 = 1
    if same(a, 1) return
}
