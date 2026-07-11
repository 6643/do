User {
    id i32
    .token i32
}

new_user(id i32, token i32) -> User {
    return User{id = id, .token = token}
}

test "private field ctor dot name" {
    return
}
