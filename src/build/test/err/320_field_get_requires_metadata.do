User {
    id i32
}

test "field get requires metadata" {
    user User = User{id = 1}
    fake i32 = 0
    value = @field_get(user, fake)
    _ = value
    return
}
