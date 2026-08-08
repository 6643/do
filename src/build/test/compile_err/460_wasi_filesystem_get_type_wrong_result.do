get_type = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.get-type", (Dir) -> WrongType | FileError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
WrongType = Unknown | Directory | RegularFile | Socket
FileError error = Io | NoEntry

run(directory Dir) -> WrongType | FileError {
    pending Future<WrongType | FileError> = get_type(directory)
    return @await(pending)
}

start() {}
