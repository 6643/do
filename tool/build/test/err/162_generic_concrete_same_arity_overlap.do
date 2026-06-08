pick(x i32) -> i32 {
    return @add(x, 1)
}

#T
pick(x T) -> T {
    return x
}

test "generic concrete same arity overlap" {
    i i32 = 1
    x = pick(i)
    return
}
