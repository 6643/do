#T
id(x T) -> T {
    return x
}

test "generic call inferred typed arg" {
    i i32 = 1
    x = id(i)
    return
}
