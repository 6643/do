User {
    id i32
}

test "struct ctor unknown field" {
    user User = User{id = 1, name = 2}
    if @eq(@get(user, .id), 1) return
}
