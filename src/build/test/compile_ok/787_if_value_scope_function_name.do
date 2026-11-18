foo() -> i32 { return 1 }
start() {
    cond bool = true
    value i32 = if cond {
        foo i32 = 7
        foo
    } else 9
    after i32 = foo()
    _ = value
    _ = after
    return
}
