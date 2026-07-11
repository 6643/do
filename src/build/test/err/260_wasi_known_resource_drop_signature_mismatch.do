host_file_drop = @wasi("filesystem/types/descriptor.drop", (descriptor) -> result<_, error-code>)

test "wasi known resource drop signature mismatch" {
    return
}
