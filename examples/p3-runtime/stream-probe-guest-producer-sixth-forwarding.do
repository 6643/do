sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
ProbeError error = Io | IllegalByteSequence | Pipe
StreamError error = StreamClosed | StreamWriteFailed

async finish_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    remaining u64 = count
    loop {
        if @eq(remaining, 0) {
            break
        }
        write_pending Future<Result<nil, StreamError>> = writer(value)
        write_result Result<nil, StreamError> = await(write_pending)
        _ = write_result
        remaining = @sub(remaining, 1)
    }
    defer close(writer)
    sink_pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return await(sink_pending)
}

async inner_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    pending Future<Result<nil, ProbeError>> = finish_stream(writer, count, value)
    return await(pending)
}

async middle_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    pending Future<Result<nil, ProbeError>> = inner_stream(writer, count, value)
    return await(pending)
}

async forward_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    pending Future<Result<nil, ProbeError>> = middle_stream(writer, count, value)
    return await(pending)
}

async entry_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    pending Future<Result<nil, ProbeError>> = forward_stream(writer, count, value)
    return await(pending)
}

async extra_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    pending Future<Result<nil, ProbeError>> = entry_stream(writer, count, value)
    return await(pending)
}

async outer_stream(writer StreamWriter<u8>, count u64, value u8) -> Result<nil, ProbeError> {
    pending Future<Result<nil, ProbeError>> = extra_stream(writer, count, value)
    return await(pending)
}

async produce(count u64, value u8) -> Result<nil, ProbeError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    pending Future<Result<nil, ProbeError>> = outer_stream(writer, count, value)
    return await(pending)
}

start() {}
