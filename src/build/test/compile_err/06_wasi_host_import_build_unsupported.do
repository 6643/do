host_file_read = @host("wasi:filesystem/types@0.3.0", "descriptor.read", (descriptor, filesize, filesize) -> result<tuple<list<u8>, bool>, error-code>)

start() {
    host_file_read(1, 0, 1)
    return
}
