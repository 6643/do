sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)

write(writer StreamWriter<u8>) -> Result<nil, ProbeError> {
    defer close(writer)
    pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return @await(pending)
}

ProbeError error = Io

start() {}
