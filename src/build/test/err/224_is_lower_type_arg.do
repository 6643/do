User {
    id i32
}

test "is lower type arg" {
    v User | i32 = 1
    lower User = User{id = 1}
    if @is(v, lower) return
    return
}
