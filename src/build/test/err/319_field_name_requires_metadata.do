User {
    id i32
}

test "field name requires metadata" {
    fake i32 = 0
    name text = @field_name(fake)
    _ = name
    return
}
