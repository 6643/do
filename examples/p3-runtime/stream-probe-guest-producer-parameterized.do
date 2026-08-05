sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
ProbeError error = Io | IllegalByteSequence | Pipe
StreamError error = StreamClosed | StreamWriteFailed

async produce(count u64, value u8) -> Result<nil, ProbeError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    remaining u64 = count
    loop {
        if @eq(remaining, 0) {
            break
        }
        pending Future<Result<nil, StreamError>> = writer(value)
        result Result<nil, StreamError> = await(pending)
        _ = result
        remaining = @sub(remaining, 1)
    }
    defer close(writer)
    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return await(sink_pending)
}

start() {}
