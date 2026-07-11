host_log = @env("log", (i32, i32) -> nil)

outer() -> nil {
    host_log("outer")
    return
}

inner() -> nil {
    host_log("inner")
    return
}

start() {
    defer outer()
    loop {
        defer inner()
        break
    }
    return
}
