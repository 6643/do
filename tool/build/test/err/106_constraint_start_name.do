#T = i32 | i64
#start(T) -> T
id(x T) -> T {
    return x
}

test "constraint start name" {
    value i32 = id(1)
    if @eq(value, 1) return
}
