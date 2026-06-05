User {
    name [u8]
}

test "path index type mismatch" {
    users [User] = .{User{name = "tom"}}
    first_name = get(users, .{0, 1})
    return
}
