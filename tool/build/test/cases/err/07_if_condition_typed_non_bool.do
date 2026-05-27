User {
    name Text
}

test "if condition typed non bool" {
    user = User{name = "tom"}
    name Text = get(user, .name)
    if name return
}
