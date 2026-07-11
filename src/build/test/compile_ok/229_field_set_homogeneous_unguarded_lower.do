User {
    left i32
    right i32
}

start() {
    user User = User{left = 1, right = 2}
    loop field = fields(User) {
        user = @field_set(user, field, 7)
    }
    return
}
