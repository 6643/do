User {
    value i32
}

test "struct ctor reserved set" {
    user User = User{set = 1}
    if @eq(@get(user, .value), 1) return
}
