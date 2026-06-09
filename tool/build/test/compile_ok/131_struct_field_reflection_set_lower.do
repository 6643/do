User {
    id i32
    active bool
}

start() {
    user User = User{id = 1, active = false}
    loop field = fields(User) {
        if @eq(@field_name(field), "id") {
            user = @field_set(user, field, 7)
        }
        if @eq(@field_name(field), "active") {
            user = @field_set(user, field, true)
        }
    }
    id i32 = @get(user, .id)
    active bool = @get(user, .active)
    return
}
