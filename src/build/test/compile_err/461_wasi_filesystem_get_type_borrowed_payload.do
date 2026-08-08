get_type = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.get-type", (Dir) -> borrow<Dir> | FileError)
Dir = @wasi_resource("filesystem/types/descriptor", { .id i64 })
FileError error = Io | NoEntry

run(directory Dir) -> borrow<Dir> | FileError {
    pending Future<borrow<Dir> | FileError> = get_type(directory)
    return @await(pending)
}

start() {}
