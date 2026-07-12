// open-at: exclusive union File|i32 at host surface (ok = File handle, err = status).
// Multi-lhs status/descriptor binding remains lowerable via WIT result-area strategy.
host_file_open_at = @wasi_func("filesystem/types/descriptor.open-at", (i32, i32, text, i32, i32) -> File | i32)
File = @wasi_resource("filesystem/types/descriptor", {
    .id i64
})

start() {
    descriptor i32 = 0
    status i32 = 0
    descriptor, status = host_file_open_at(1, 0, "data.txt", 0, 0)
    return
}
