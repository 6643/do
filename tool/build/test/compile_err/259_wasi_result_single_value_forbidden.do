host_file_write = @wasi("filesystem/types/descriptor.write", (descriptor, list<u8>, filesize) -> result<filesize, error-code>)

start() {
    data [u8] = "abc"
    written u64 = host_file_write(1, data, 0)
    return
}
