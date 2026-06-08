User {
    id i32
}

make_user() -> User {
    return User{id = 1}
}

test "is call type arg" {
    v User | i32 = 1
    if @is(v, make_user()) return
    return
}
