.InternalUser = User | nil

User {
    name Text
}

test "private type decl left dot" {
    user = User{name = "tom"}
    name = get(user, .name)
    expected Text = "tom"
    if eq(name, expected) return
}
