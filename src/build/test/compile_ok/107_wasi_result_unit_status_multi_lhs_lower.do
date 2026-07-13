// Unit fallible host: exclusive union nil|i32; multi-lhs status binding remains lowerable.
host_file_sync = @host("wasi:filesystem/types@0.3.0", "descriptor.sync", (i32) -> nil | i32)

start() {
    status i32 = 0
    _, status = host_file_sync(1)
    return
}
