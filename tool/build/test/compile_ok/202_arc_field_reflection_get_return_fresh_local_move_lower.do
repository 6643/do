User {
    name text
}

take_name() -> text {
    user User = User{name = "amy"}
    loop field = fields(User) {
        if @eq(@field_name(field), "name") {
            return @field_get(user, field)
        }
    }
    return ""
}

start() {
    name text = take_name()
    return
}
