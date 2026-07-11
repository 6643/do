User {
    id i32
}

test "inferred struct ctor duplicate field" {
    user User = .{id = 1, id = 2}
    if @eq(@get(user, .id), 2) return
}
