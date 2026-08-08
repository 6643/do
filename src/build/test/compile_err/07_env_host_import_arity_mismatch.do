host_add = @host_func("env", "add", (i32, i32) -> i32)

start() {
    x i32 = host_add(1)
    return
}
