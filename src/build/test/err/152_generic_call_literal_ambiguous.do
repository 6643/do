#T
id(x T) -> T {
    return x
}

test "generic call literal ambiguous" {
    x i32 = id(1)
    return
}
