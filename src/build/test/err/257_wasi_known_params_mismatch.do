host_file_write = @wasi_func("filesystem/types/descriptor.write", (descriptor, list<u8>) -> result<filesize, error-code>)

test "wasi known params mismatch" {
    return
}
