nop() -> nil {
    return nil
}

User {
    name text
}

take_name(user User) -> text {
    defer nop()
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
