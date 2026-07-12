host_file_read = @wasi_func("filesystem/types/descriptor.read", (descriptor, filesize, filesize) -> result<tuple<list<u8>, bool>, error-code>)

sync_descriptor() {
    host_file_read(1, 0, 1)
    return
}
