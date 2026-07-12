host_file_drop = @wasi_func("filesystem/types/descriptor.drop", (descriptor) -> result<_, error-code>)

test "wasi known resource drop signature mismatch" {
    return
}
