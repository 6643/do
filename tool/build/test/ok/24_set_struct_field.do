User {
    name [u8]
}

test "set struct field" {
    user = User{name = "tom"}
    user = set(user, .name, "amy")
    expected [u8] = "amy"
    if eq(get(user, .name), expected) return
}
