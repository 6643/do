host_file_open_at = @wasi_func("filesystem/types/descriptor.open-at", (descriptor, path-flags, text, open-flags, descriptor-flags) -> result<descriptor,error-code>)

start() {
    descriptor i32 = 0
    status i32 = 0
    descriptor, status = host_file_open_at(1, 0, "data.txt", 0, 0)
    return
}
