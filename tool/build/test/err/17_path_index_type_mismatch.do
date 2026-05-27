User {
    name Text
}

test "path index type mismatch" {
    users List<User> = List<User>{}
    users = put(users, User{name = "tom"})
    first_name = get(users, .{"0", .name})
    return
}
