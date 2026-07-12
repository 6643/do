// Unit fallible host: exclusive union nil|i32; multi-lhs status binding remains lowerable.
host_file_sync = @wasi_func("filesystem/types/descriptor.sync", (i32) -> nil | i32)

start() {
    status i32 = 0
    _, status = host_file_sync(1)
    return
}
