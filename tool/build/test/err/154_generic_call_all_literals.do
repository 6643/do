#T
#add(T, T) -> T
sum(a T, b T) -> T {
    return @add(a, b)
}

test "generic call all literals" {
    x i32 = sum(1, 2)
    return
}
