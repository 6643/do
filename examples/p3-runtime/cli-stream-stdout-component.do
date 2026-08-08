stdout_write = @host_async_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
StdoutError error = Io | IllegalByteSequence | Pipe

write(writer StreamWriter<u8>) -> Result<nil, StdoutError> {
    defer close(writer)
    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
    return @await(pending)
}

start() {}
