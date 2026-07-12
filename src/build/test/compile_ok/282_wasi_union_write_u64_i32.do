// Prefer exclusive union result for write: ok = filesize u64, err = status i32.
// List arg is a [u8] storage local (string-literal list sugar not on this host path).
host_write = @wasi_func("filesystem/types/descriptor.write", (i32, [u8], u64) -> u64 | i32)
start() {
    data [u8] = "ab"
    n u64 | i32 = host_write(1, data, 0)
    _ = n
    return
}
