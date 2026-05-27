#T = i32 | i64
#add(T, T) -> T
sum(a T, b T) -> T {
    return add(a, b)
}

add(a i32, b i32) i32 => a
add(a i64, b i64) i64 => a

test "func constraint prefix line" {
    expected i32 = 1
    if eq(sum(1, 2), expected) return
}
