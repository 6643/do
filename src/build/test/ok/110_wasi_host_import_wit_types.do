host_file_write = @wasi_func("filesystem/types/descriptor.write", (descriptor, list<u8>, filesize) -> result<filesize, error-code>)
host_file_read = @wasi_func("filesystem/types/descriptor.read", (descriptor, filesize, filesize) -> result<tuple<list<u8>, bool>, error-code>)
host_file_sync = @wasi_func("filesystem/types/descriptor.sync", (descriptor) -> result<_, error-code>)
host_file_link = @wasi_func("filesystem/types/descriptor.link-at", (descriptor, path-flags, text, borrow<descriptor>, text) -> result<_, error-code>)
host_char_echo = @wasi_func("text/char/echo", (char) -> char)
host_now = @wasi_func("clocks/system-clock/now", () -> Datetime)

Datetime {
    seconds i64
    nanoseconds u32
}

test "wasi host import wit types" {
    return
}
