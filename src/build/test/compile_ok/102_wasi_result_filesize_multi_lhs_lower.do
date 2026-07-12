host_file_write = @wasi_func("filesystem/types/descriptor.write", (descriptor, list<u8>, filesize) -> result<filesize, error-code>)

start() {
    data [u8] = "abc"
    written u64 = 0
    status i32 = 0
    written, status = host_file_write(1, data, 0)
    return
}
