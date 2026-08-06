stdout_write = @host_func("wasi:cli/stdout@0.3.0-rc-2025-09-16", "write-via-stream", (StreamWriter<u8>) -> Result<nil, StdoutError>)
StdoutError error = Io | IllegalByteSequence | Pipe
StreamError error = StreamClosed | StreamWriteFailed

produce() -> Result<nil, StdoutError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    first u8 = 65
    write_pending Future<Result<nil, StreamError>> = writer(first)
    write_result Result<nil, StreamError> = @await(write_pending)
    _ = write_result
    second u8 = 66
    write_pending_2 Future<Result<nil, StreamError>> = writer(second)
    write_result_2 Result<nil, StreamError> = @await(write_pending_2)
    _ = write_result_2
    third u8 = 67
    write_pending_3 Future<Result<nil, StreamError>> = writer(third)
    write_result_3 Result<nil, StreamError> = @await(write_pending_3)
    _ = write_result_3
    defer close(writer)
    pending Future<Result<nil, StdoutError>> = stdout_write(writer)
    return @await(pending)
}

start() {}
