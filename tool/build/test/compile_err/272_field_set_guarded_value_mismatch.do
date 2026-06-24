User {
    id i32
    active bool
}

start() {
    user User = User{id = 1, active = false}
    loop field = fields(User) {
        if @eq(@field_name(field), "active") {
            user = @field_set(user, field, 7)
        }
    }
    return
}
