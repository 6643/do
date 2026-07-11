User {
    name text
}

take_name(user User) -> text {
    loop field = fields(User) {
        if @eq(@field_name(field), "name") {
            return @field_get(user, field)
        }
    }
    return ""
}

start() {
    user User = User{name = "amy"}
    name text = take_name(user)
    return
}
