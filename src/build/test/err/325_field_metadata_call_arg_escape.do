User {
    id i32
}

take(value i32) -> i32 {
    return value
}

test "field metadata call arg escape" {
    loop field = fields(User) {
        _ = take(field)
    }
    return
}
