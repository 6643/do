host_file_write = @wasi_func("filesystem/types/descriptor.write", (descriptor, list<u8>, filesize) -> result<filesize, error-code>)

start() {
    data [u8] = "abc"
    host_file_write(1, data, 0)
    return
}
