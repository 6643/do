User {
    name text
}

take_name() -> text {
    user User = User{name = "amy"}
    return @get(user, .name)
}

start() {
    name text = take_name()
    return
}
