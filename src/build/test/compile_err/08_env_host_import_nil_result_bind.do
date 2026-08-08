host_log = @host_func("env", "log", (i32) -> nil)

start() {
    x i32 = host_log(1)
    return
}
