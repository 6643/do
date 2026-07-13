host_file_write = @host("wasi:filesystem/types@0.3.0", "descriptor.write", (descriptor, list<u8>, filesize) -> result<filesize, error-code>)

start() {
    data [u8] = "abc"
    written u64 = host_file_write(1, data, 0)
    return
}
