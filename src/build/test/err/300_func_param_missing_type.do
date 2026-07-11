missing_type(value) -> i32 {
    return 1
}

test "func param missing type" {
    got = missing_type(1)
    if @eq(got, 1) return
}
