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

test "compiled field reflection get return fresh local move" {
    got text = take_name()
    if @eq(got, "amy") return
}
