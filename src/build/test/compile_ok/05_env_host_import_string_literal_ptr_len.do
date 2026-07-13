host_log = @host("env", "log", (i32, i32) -> nil)

start() {
    host_log("abc")
    return
}
