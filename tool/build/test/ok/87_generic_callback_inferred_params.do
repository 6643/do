#T
#U
#Q = (T) -> U
project(x T, f Q) -> U {
    return f(x)
}

test "generic callback inferred params" {
    i i32 = 1
    out = project(i, (x) -> bool => @gt(x, 0))
    return
}
