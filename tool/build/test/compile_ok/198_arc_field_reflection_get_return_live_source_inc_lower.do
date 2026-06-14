User {
    name text
    id i32
}

take_name(user User) -> text {
    loop field = fields(User) {
        if @eq(@field_name(field), "name") {
            got = @field_get(user, field)
            id i32 = @get(user, .id)
            if @eq(id, 0) return ""
            return got
        }
    }
    return ""
}

start() {
    user User = User{name = "amy", id = 1}
    name text = take_name(user)
    return
}
