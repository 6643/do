User {
    name [u8]
}

test "field segment ordinary call" {
    user = User{name = "tom"}
    user = put(user, .name, "amy")
    return
}
