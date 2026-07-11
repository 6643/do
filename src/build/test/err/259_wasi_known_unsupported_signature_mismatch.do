host_dir_read = @wasi("filesystem/types/descriptor.read-directory", (descriptor) -> result<_, error-code>)

test "wasi known unsupported signature mismatch" {
    return
}
