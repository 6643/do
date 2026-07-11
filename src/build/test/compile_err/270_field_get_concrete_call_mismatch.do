User {
    id i32
    name text
}

take_text(value text) -> text {
    return value
}

start() {
    user User = User{id = 1, name = "amy"}
    loop field = fields(User) {
        _ = take_text(@field_get(user, field))
    }
    return
}
