User {
    name Text
}

test "path index infix expr" {
    users List<User> = List<User>{}
    users = put(users, User{name = "tom"})
    i usize = 0
    first_name = get(users, .{i + 1, .name})
    return
}
