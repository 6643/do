// Unit fallible host: exclusive union nil|i32 (statement discard keeps fixture 100 behavior).
// Manifest still stores WIT result<_,error-code>.
host_file_sync = @wasi_func("filesystem/types/descriptor.sync", (i32) -> nil | i32)

start() {
    host_file_sync(1)
    return
}
