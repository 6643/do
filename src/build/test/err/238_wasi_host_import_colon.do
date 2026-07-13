// Invalid wasi locator (no package/interface slash form).
host_file_sync = @host("wasi:filesystem:types@0.3.0", "descriptor.sync", (descriptor) -> result<_, error-code>)

test "wasi host import colon" {}
