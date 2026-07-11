User {
    value i32
}

test "struct ctor reserved get" {
    user User = User{get = 1}
    if @eq(@get(user, .value), 1) return
}
