User {
    name text
}

take_name() -> text {
    user User = User{name = "amy"}
    return @get(user, .name)
}

test "compiled struct get return fresh local move" {
    got text = take_name()
    if @eq(got, "amy") return
}
