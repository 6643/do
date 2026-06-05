User {
    name [u8]
}

test "path get single" {
    user = User{name = "tom"}
    name = get(user, .name)
    expected [u8] = "tom"
    if eq(name, expected) return
}
