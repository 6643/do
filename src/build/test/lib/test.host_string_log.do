host_log = @host_func("env", "log", (i32, i32) -> nil)

log_abc() {
    host_log("abc")
    return
}
