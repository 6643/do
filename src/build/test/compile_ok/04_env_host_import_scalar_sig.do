host_file_close = @host("env", "file_close", (i64) -> i32)
host_mix = @host("env", "mix", (f32, f64) -> i64)
host_now = @host("env", "now", () -> f64)

start() {
    return
}
