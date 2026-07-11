#T
make_default() -> T {
    return 0
}

test "return only type param" {
    x i32 = make_default()
    return
}
