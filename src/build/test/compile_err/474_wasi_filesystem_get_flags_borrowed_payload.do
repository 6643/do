get_flags = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.get-flags", (Dir) -> borrow<Dir> | FlagsError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
FlagsError error = Io | NoEntry

run(directory Dir) -> borrow<Dir> | FlagsError {
    pending Future<borrow<Dir> | FlagsError> = get_flags(directory)
    return @await(pending)
}

start() {}
