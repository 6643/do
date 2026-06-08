User {
    name [u8]
}

take(user User, name [u8]) -> User {
    return user
}

test "field segment ordinary call" {
    user = User{name = "tom"}
    user = take(user, .name)
    return
}
