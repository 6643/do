User {
    name text
}

set_name(user User) -> nil {
    @set(user, .name, "sam")
    return
}

test "function parameter set statement" {
    user = User{name = "tom"}
    set_name(user)
    return
}
