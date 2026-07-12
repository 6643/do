// Filesize fallible host: exclusive union u64|i32 at host surface.
// Multi-lhs still lowerable via WIT result-area strategy (transitional call form).
host_file_write = @wasi_func("filesystem/types/descriptor.write", (i32, [u8], u64) -> u64 | i32)

start() {
    data [u8] = "abc"
    written u64 = 0
    status i32 = 0
    written, status = host_file_write(1, data, 0)
    return
}
