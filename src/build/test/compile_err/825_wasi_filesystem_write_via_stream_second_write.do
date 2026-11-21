write_via_stream = @host_async_func("wasi:filesystem/types@0.3.0-rc-2025-09-16", "descriptor.write-via-stream", (File, StreamWriter<u8>, u64) -> Result<nil, FileError>)
File = @wasi_resource("filesystem/types/descriptor", { .id i64 })
FileError error = Io
StreamError error = Closed | Failed
run(file File, offset u64) -> nil {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    defer close(writer)
    pending Future<Result<nil, FileError>> = write_via_stream(file, writer, offset)
    first u8 = 65
    write_pending Future<Result<nil, StreamError>> = writer(first)
    write_result Result<nil, StreamError> = @await(write_pending)
    _ = write_result
    second u8 = 66
    write_pending_2 Future<Result<nil, StreamError>> = writer(second)
    completed Result<nil, FileError> = @await(pending)
    _ = completed
    return
}
start() {}
