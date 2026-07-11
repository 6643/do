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

test "compiled field reflection get return last use move" {
    user User = User{name = "amy"}
    got text = take_name(user)
    if @eq(got, "amy") return
}
