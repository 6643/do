User {
    id i32
    .token i32 = 0
}

new_user(id i32) -> User {
    return User{id = id}
}
