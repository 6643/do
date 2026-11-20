User {
    name [u8]
}

set_name(user User, name [u8]) -> User {
    return @set(user, .name, name)
}

test "function parameter returns updated value" {
    user = User{name = "tom"}
    user = set_name(user, "sam")
    expected [u8] = "sam"
    if @eq(@get(user, .name), expected) return
    return
}
