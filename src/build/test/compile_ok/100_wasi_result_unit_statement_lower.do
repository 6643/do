host_file_sync = @wasi("filesystem/types/descriptor.sync", (descriptor) -> result<_, error-code>)

start() {
    host_file_sync(1)
    return
}
