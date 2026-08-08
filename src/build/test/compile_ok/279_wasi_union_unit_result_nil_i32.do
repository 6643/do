host_file_sync = @host_func("wasi:filesystem/types@0.3.0", "descriptor.sync", (i32) -> nil | i32)

start() {
    host_file_sync(1)
    s nil | i32 = host_file_sync(1)
    _ = s
    return
}
