User {
    id i32
}

find_user() -> User | nil | nil {
    return nil
}

test "duplicate nil union" {
    u = find_user()
    if eq(u, nil) return
}
