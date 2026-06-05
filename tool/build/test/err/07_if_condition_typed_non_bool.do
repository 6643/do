User {
    name [u8]
}

test "if condition typed non bool" {
    user = User{name = "tom"}
    name [u8] = get(user, .name)
    if name return
}
