#T
#U
#Q = (T) -> U
project(x T, f Q) -> U {
    return f(x)
}

test "generic callback inferred return" {
    i i32 = 1
    out bool = project(i, (x i32) => @gt(x, 0))
    return
}
