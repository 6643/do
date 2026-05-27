check_nested_if(value i32) -> i32 {
    loop {
        if eq(value, 1) {
            out i32 = 1
        }
        if eq(value, 2) {
            out i32 = 2
        }
        return value
    }
}

test "nested if blocks are not structs" {
    x i32 = check_nested_if(1)
    return
}
