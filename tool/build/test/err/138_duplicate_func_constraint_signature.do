#T = i32 | i64
#add(T, T) -> T
#add(T, T) -> T
sum(a T, b T) -> T {
    return add(a, b)
}

test "duplicate func constraint signature" {
    return
}
