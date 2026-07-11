host_log = @env("log", (i32, i32) -> nil)

log_bytes(data [u8]) {
    host_log(data)
    return
}

start() {
    data [u8] = "abc"
    log_bytes(data)
    return
}
