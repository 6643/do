set(a User, name Text) -> User {
    return a
}

User {
    id u32
}

test "open func set" {
    user = User{id = 1}
    return
}
