#T
#U
#Q = (T) -> U
project(x T, f Q) -> U {
    return f(x)
}

test "generic callback explicit return" {
    i i32 = 1
    out = project(i, (x i32) -> bool => @gt(x, 0))
    return
}
