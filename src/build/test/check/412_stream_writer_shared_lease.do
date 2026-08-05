sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
ProbeError error = Io | IllegalByteSequence | Pipe

async sink_once(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
    defer close(writer)
    pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return await(pending)
}

async produce() -> Result<nil, ProbeError> {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    first Future<Result<nil, ProbeError>> = sink_once(writer)
    second Future<Result<nil, ProbeError>> = sink_once(writer)
    result Result<nil, ProbeError> = await(first)
    _ = second
    return result
}

start() {}
