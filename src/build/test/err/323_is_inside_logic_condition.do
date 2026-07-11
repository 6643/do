User {
    id i32
}

ready() -> bool {
    return true
}

test "is inside logic condition" {
    value User | nil = User{id = 1}
    if @and(@is(value, User), ready()) {
        user User = value
        _ = user
    }
    return
}
