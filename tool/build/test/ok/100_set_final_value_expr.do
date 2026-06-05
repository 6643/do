User {
    name [u8]
}

to_text() -> [u8] {
    return "amy"
}

test "set final value expr" {
    user = User{name = "tom"}
    user = set(user, .name, "amy")
    user = set(user, .name, to_text())
    expected [u8] = "amy"
    if eq(get(user, .name), expected) return
    return
}
