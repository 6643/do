host_log = @host("env", "log", (i32, i32) -> nil)

start() {
    value i32 = 1
    host_log(value)
    return
}
