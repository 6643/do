get_flags = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.get-flags", (Dir) -> WrongFlags | FlagsError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
WrongFlags = Read | Write | Directory
FlagsError error = Io | NoEntry

run(directory Dir) -> WrongFlags | FlagsError {
    pending Future<WrongFlags | FlagsError> = get_flags(directory)
    return @await(pending)
}

start() {}
