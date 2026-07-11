#T
identity(value) -> T {
    return value
}

test "generic param missing type" {
    got = identity<i32>(1)
    if @eq(got, 1) return
}
