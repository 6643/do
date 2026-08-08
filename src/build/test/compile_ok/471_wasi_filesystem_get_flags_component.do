get_flags = @host("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.get-flags", (Dir) -> u8 | FlagsError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
FlagsError error = Io | NoEntry

run(directory Dir) -> u8 | FlagsError {
    pending Future<u8 | FlagsError> = get_flags(directory)
    return @await(pending)
}

start() {}
