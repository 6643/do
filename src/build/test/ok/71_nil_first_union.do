User {
    id i32
}

find_user(id i32) -> User | nil {
    if @eq(id, 0) return nil
    return User{id = id}
}

test "nil last union" {
    u = find_user(0)
    if @eq(u, nil) return
}
