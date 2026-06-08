#add(i32, i32) -> i32
sum(a i32, b i32) -> i32 {
    return @add(a, b)
}

test "func constraint requires type param" {
    expected i32 = 3
    if @eq(sum(1, 2), expected) return
}
