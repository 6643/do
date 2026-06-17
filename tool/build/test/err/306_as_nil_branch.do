User {
    id i32
}

find_user(found bool) -> User | nil {
    user User = User{id = 1}
    if found return user
    return nil
}

test "as nil branch invalid" {
    value User | nil = find_user(false)
    user User = @as(value, nil)
    return
}
