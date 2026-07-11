#T
#combine(T, T) -> T
sum(a T, b T) -> T {
    return combine(a, b)
}

combine(a i32, b i32) -> i32 {
    return @add(a, b)
}

test "func constraint unbounded type param" {
    a i32 = 1
    b i32 = 2
    expected i32 = 3
    if @eq(sum(a, b), expected) return
}
