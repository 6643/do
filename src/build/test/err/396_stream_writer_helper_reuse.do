sink_write = @host_async_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
ProbeError error = Io | IllegalByteSequence | Pipe
StreamError error = StreamClosed | StreamWriteFailed

write_stream(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
    defer close(writer)
    pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return @await(pending)
}

produce() -> Result<nil, ProbeError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    pending Future<Result<nil, ProbeError>> = @async(write_stream(writer))
    close(writer)
    return @await(pending)
}

start() {}
