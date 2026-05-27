User {
    name Text
}

test "path bad segment" {
    user = User{name = "tom"}
    name = get(user, .{.name, .})
    return
}
