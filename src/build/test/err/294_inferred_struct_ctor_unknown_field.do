User {
    id i32
}

test "inferred struct ctor unknown field" {
    user User = .{id = 1, name = 2}
    if @eq(@get(user, .id), 1) return
}
