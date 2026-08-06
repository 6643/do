sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
ProbeError error = Io | IllegalByteSequence | Pipe
StreamError error = StreamClosed | StreamWriteFailed

write_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
    defer close(writer)
    pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return @await(pending)
}

produce() -> Result<nil, ProbeError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    write_pending Future<Result<nil, StreamError>> = writer(65)
    write_result Result<nil, StreamError> = @await(write_pending)
    _ = write_result
    write_pending_2 Future<Result<nil, StreamError>> = writer(66)
    write_result_2 Result<nil, StreamError> = @await(write_pending_2)
    _ = write_result_2
    pending Future<Result<nil, ProbeError>> = @async(write_stream(writer))
    return @await(pending)
}

start() {}
