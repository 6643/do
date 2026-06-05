User {
    name [u8]
}

test "if condition get text not bool" {
    user = User{name = "tom"}
    name = get(user, .name)
    if name return
}
