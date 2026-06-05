User {
    name i32
}

test "dot ident internal dot" {
    user User = User{name = 1}
    value = get(user, .a.b)
    return
}
