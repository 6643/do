nop() -> nil {
    return nil
}

User {
    name text
}

take_name() -> text {
    user User = User{name = "amy"}
    defer nop()
    return @get(user, .name)
}

start() {
    name text = take_name()
    return
}
