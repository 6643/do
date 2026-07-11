User {
    id i32
    name text
}

start() {
    user User = User{id = 1, name = "amy"}
    loop field = fields(User) {
        value = @field_get(user, field)
        _ = value
    }
    return
}
