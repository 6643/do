host_file_write = @wasi("filesystem/types/descriptor.write", (descriptor, list<u8>) -> result<filesize, error-code>)

test "wasi known params mismatch" {
    return
}
