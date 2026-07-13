host_file_write = @host("wasi:filesystem/types@0.3.0", "descriptor.write", (descriptor, list<u8>) -> result<filesize, error-code>)

test "wasi known params mismatch" {
    return
}
