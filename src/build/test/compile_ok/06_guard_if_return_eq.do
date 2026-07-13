host_log = @host("env", "log", (i32) -> nil)

start() {
    if @eq(1, 1) return
    host_log(7)
    return
}
