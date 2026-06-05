#T
#combine(T, T) -> T
sum(a T, b T) -> T {
    return combine(a, b)
}

combine(a i32, b i32) -> i32 {
    return add(a, b)
}

test "generic call mixed literal" {
    a i32 = 1
    x = sum(a, 2)
    return
}
