open_at_descriptor = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.open-at", (Dir, u32, text, u32, u32) -> File | OpenError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
OpenError error = Io | NoEntry

async run(root Dir, path_flags u32, path text, open_flags u32, descriptor_flags u32) -> File | OpenError {
    pending Future<File | OpenError> = open_at_descriptor(root, path_flags, path, open_flags, descriptor_flags)
    return @await(pending)
}

start() {}
