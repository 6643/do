// Filesize fallible host: exclusive union u64|i32 (statement discard).
// Manifest still stores WIT result<filesize,error-code>.
host_file_write = @host("wasi:filesystem/types@0.3.0", "descriptor.write", (i32, [u8], u64) -> u64 | i32)

start() {
    data [u8] = "abc"
    host_file_write(1, data, 0)
    return
}
