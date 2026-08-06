sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
ProbeError error = Io | IllegalByteSequence | Pipe
StreamError error = StreamClosed | StreamWriteFailed

finish_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
    first u8 = 65
    write_pending Future<Result<nil, StreamError>> = writer(first)
    write_result Result<nil, StreamError> = @await(write_pending)
    _ = write_result
    second u8 = 66
    write_pending_2 Future<Result<nil, StreamError>> = writer(second)
    write_result_2 Result<nil, StreamError> = @await(write_pending_2)
    _ = write_result_2
    defer close(writer)
    pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return @await(pending)
}

forward_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
    pending Future<Result<nil, ProbeError>> = @async(finish_stream(writer))
    return @await(pending)
}

produce() -> Result<nil, ProbeError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    pending Future<Result<nil, ProbeError>> = @async(forward_stream(writer))
    return @await(pending)
}

start() {}
