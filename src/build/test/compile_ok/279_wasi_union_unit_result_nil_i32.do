host_file_sync = @wasi_func("filesystem/types/descriptor.sync", (i32) -> nil | i32)

start() {
    host_file_sync(1)
    s nil | i32 = host_file_sync(1)
    _ = s
    return
}
