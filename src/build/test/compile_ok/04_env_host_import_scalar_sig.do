host_file_close = @host_func("env", "file_close", (i64) -> i32)
host_mix = @host_func("env", "mix", (f32, f64) -> i64)
host_now = @host_func("env", "now", () -> f64)

start() {
    return
}
