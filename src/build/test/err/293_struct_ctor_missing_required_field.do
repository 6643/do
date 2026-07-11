User {
    id i32
    name i32
}

test "struct ctor missing required field" {
    user User = User{id = 1}
    if @eq(@get(user, .id), 1) return
}
