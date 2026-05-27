User {
    name Text
}

test "path access call" {
    user = User{name = "tom"}
    user.get_name()
    return
}
