User {
    name Text
}

test "path index complex expr segment" {
    users List<User> = List<User>{}
    users = put(users, User{name = "tom"})
    users = put(users, User{name = "amy"})
    i usize = 0
    first_name = get(users, .{add(i, 1), .name})
    expected Text = "amy"
    if eq(first_name, expected) return
}
