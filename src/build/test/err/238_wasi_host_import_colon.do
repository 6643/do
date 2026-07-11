host_file_sync = @wasi("filesystem:types/descriptor.sync", (descriptor) -> result<_, error-code>)

test "wasi host import colon" {}
