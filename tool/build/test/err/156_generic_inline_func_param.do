#T
#U
project(x T, f (T) -> U) -> U {
    return f(x)
}

test "generic inline func param" {
    i i32 = 1
    out = project(i, (x) -> bool => @gt(x, 0))
    return
}
