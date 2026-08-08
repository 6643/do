host_log = @host_func("env", "log", (i32, i32) -> nil)

one() -> nil {
    host_log("one")
    return
}

two() -> nil {
    host_log("two")
    return
}

start() {
    defer one()
    defer two()
    return
}
