sink_write = @host_async_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
ProbeError error = Io | IllegalByteSequence | Pipe
StreamError error = StreamClosed | StreamWriteFailed

finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    remaining u64 = count
    loop {
        if @eq(remaining, 0) {
            break
        }
        write_pending Future<Result<nil, StreamError>> = writer(value)
        write_result Result<nil, StreamError> = @await(write_pending)
        _ = write_result
        remaining = @sub(remaining, 1)
    }
    if @eq(value, 90) {
        close(writer)
    } else {
        abort(writer, 2)
    }
    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return @await(sink_pending)
}

produce(count u64, value u8) -> Result<nil, ProbeError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    pending Future<Result<nil, ProbeError>> = @async(finish_stream(writer, count, value))
    return @await(pending)
}

start() {}
