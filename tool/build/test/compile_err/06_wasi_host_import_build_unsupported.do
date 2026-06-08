host_file_read = @wasi("filesystem/types/descriptor.read", (descriptor, filesize, filesize) -> result<tuple<list<u8>, bool>, error-code>)

start() {
    host_file_read(1, 0, 1)
    return
}
