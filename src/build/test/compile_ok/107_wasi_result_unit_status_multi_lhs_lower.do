host_file_sync = @wasi_func("filesystem/types/descriptor.sync", (descriptor) -> result<_, error-code>)

start() {
    status i32 = 0
    _, status = host_file_sync(1)
    return
}
