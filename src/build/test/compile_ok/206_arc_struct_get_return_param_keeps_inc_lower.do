User {
    name text
}

take_name(user User) -> text {
    return @get(user, .name)
}

start() {
    user User = User{name = "amy"}
    name text = take_name(user)
    return
}
