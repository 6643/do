read_via_stream = @host_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.read-via-stream", (File, u64) -> Tuple<Stream<u8>, Future<Result<nil, FileError>>>)
File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
FileError error = Io | NoEntry

run(file File, offset u64) -> nil {
    handles Tuple<Stream<u8>, Future<Result<nil, FileError>>> = read_via_stream(file, offset)
    reader Stream<u8> = @get(handles, 0)
    completion Future<Result<nil, FileError>> = @get(handles, 1)
    pending Future<Result<u8, nil>> = @next(reader)
    item Result<u8, nil> = @await(pending)
    _ = item
    completed Result<nil, FileError> = @await(completion)
    _ = completed
    return
}

cancel_probe() -> nil {}
start() {}
