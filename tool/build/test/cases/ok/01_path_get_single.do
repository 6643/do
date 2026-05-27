User {
    name Text
}

test "path get single" {
    user = User{name = "tom"}
    name = get(user, .name)
    expected Text = "tom"
    if eq(name, expected) return
}
