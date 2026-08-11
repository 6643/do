set_size_descriptor = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.set-size", (File, u64) -> nil | SetSizeError)
File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
SetSizeError error = Io | NoEntry

async run(file File, size u64) -> nil | SetSizeError {
    pending Future<nil | SetSizeError> = set_size_descriptor(file, size)
    return @await(pending)
}

start() {}
