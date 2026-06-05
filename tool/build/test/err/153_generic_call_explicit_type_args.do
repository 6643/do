#T
id(x T) -> T {
    return x
}

test "generic call explicit type args" {
    i i32 = 1
    x = id<i32>(i)
    return
}
