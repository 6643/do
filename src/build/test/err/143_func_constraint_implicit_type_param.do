#add(T, T) -> T
sum(a i32, b i32) -> i32 {
    return @add(a, b)
}

test "func constraint implicit type param" {
    expected i32 = 3
    if @eq(sum(1, 2), expected) return
}
