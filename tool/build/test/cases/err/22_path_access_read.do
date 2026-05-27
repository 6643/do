User {
    name Text
}

test "path access read" {
    user = User{name = "tom"}
    name = user.name
    return
}
