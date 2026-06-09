User {
    id i32
    name i32
}

test "inferred struct ctor missing required field" {
    user User = .{id = 1}
    if @eq(@get(user, .id), 1) return
}
