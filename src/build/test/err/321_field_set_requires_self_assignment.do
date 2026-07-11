User {
    id i32
}

test "field set requires self assignment" {
    user User = User{id = 1}
    loop field = fields(User) {
        other = @field_set(user, field, 2)
        _ = other
    }
    return
}
