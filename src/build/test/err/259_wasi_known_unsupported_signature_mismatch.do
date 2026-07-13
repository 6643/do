host_dir_read = @host("wasi:filesystem/types@0.3.0", "descriptor.read-directory", (descriptor) -> result<_, error-code>)

test "wasi known unsupported signature mismatch" {
    return
}
