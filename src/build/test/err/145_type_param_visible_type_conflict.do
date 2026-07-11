User {
    id i32
}

#User
Box {
    value User
}

test "type param visible type conflict" {
    b = Box<User>{value = User{id = 1}}
    return
}
