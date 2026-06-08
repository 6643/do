host_log = @env("log", (i32, i32) -> nil)

one() -> nil {
    host_log("one")
    return
}

start() {
    defer one()
    defer {
        host_log("block")
        return
        host_log("after")
    }
    return
}
