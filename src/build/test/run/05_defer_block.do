host_log = @host_func("env", "log", (i32, i32) -> nil)

one() -> nil {
    host_log("one")
    return
}

start() {
    defer one()
    defer {
        host_log("block")
    }
    return
}
