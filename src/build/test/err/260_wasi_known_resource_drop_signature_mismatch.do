host_file_drop = @host("wasi:filesystem/types@0.3.0", "descriptor.drop", (descriptor) -> result<_, error-code>)

test "wasi known resource drop signature mismatch" {
    return
}
