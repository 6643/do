User {
    id i32
}

test "field metadata value escape" {
    loop field = fields(User) {
        saved = field
        _ = saved
    }
    return
}
