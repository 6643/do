User {
    id i32
}

load_user() -> User | User {
    return User{id = 1}
}

test "duplicate named union" {
    user = load_user()
    if is(user, User) return
}
