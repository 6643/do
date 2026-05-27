User {
    name Text
}

test "path index expr segment" {
    users List<User> = List<User>{}
    users = put(users, User{name = "tom"})
    first_name = get(users, .{0, .name})
    expected Text = "tom"
    if eq(first_name, expected) return
}
