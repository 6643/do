host_file_write = @host("wasi:filesystem/types@0.3.0", "descriptor.write", (descriptor, list<u8>, filesize) -> result<filesize, error-code>)
host_file_read = @host("wasi:filesystem/types@0.3.0", "descriptor.read", (descriptor, filesize, filesize) -> result<tuple<list<u8>, bool>, error-code>)
host_file_sync = @host("wasi:filesystem/types@0.3.0", "descriptor.sync", (descriptor) -> result<_, error-code>)
host_file_link = @host("wasi:filesystem/types@0.3.0", "descriptor.link-at", (descriptor, path-flags, text, borrow<descriptor>, text) -> result<_, error-code>)
host_char_echo = @host("wasi:text/char@0.3.0", "echo", (char) -> char)
host_now = @host("wasi:clocks/system-clock@0.3.0", "now", () -> Datetime)

Datetime {
    seconds i64
    nanoseconds u32
}

test "wasi host import wit types" {
    return
}
