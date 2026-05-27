User {
    name Text
}

test "put struct field" {
    user = User{name = "tom"}
    user = put(user, .name, "amy")
    expected Text = "amy"
    if eq(get(user, .name), expected) return
}
