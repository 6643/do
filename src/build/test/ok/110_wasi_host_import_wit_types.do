host_file_write = @wasi("filesystem/types/descriptor.write", (descriptor, list<u8>, filesize) -> result<filesize, error-code>)
host_file_read = @wasi("filesystem/types/descriptor.read", (descriptor, filesize, filesize) -> result<tuple<list<u8>, bool>, error-code>)
host_file_sync = @wasi("filesystem/types/descriptor.sync", (descriptor) -> result<_, error-code>)
host_file_link = @wasi("filesystem/types/descriptor.link-at", (descriptor, path-flags, text, borrow<descriptor>, text) -> result<_, error-code>)
host_char_echo = @wasi("text/char/echo", (char) -> char)
host_now = @wasi("clocks/system-clock/now", () -> Datetime)

Datetime {
    seconds i64
    nanoseconds u32
}

test "wasi host import wit types" {
    return
}
