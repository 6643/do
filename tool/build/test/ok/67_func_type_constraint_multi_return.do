#F = () -> i8, bool | i32
accept(f F) {
    return
}

foo() -> i8, bool | i32 {
    return 0, false
}

test "func type constraint multi return" {
    accept(foo)
    return
}
