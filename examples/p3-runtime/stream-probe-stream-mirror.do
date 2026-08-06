probe_read = @host_func("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
sink_write = @host_func("do:stream-probe@0.1.0", "write-via-stream", (StreamWriter<u8>) -> Result<nil, ProbeError>)
ProbeError error = Io | IllegalByteSequence | Pipe
StreamError error = StreamClosed | StreamWriteFailed

produce() -> Result<nil, ProbeError> {
    source Tuple<Stream<u8>, Future<Result<nil, ProbeError>>> = probe_read()
    input Stream<u8> = @get(source, 0)
    source_done Future<Result<nil, ProbeError>> = @get(source, 1)
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    defer close(writer)
    remaining u64 = 3
    loop {
        if @eq(remaining, 0) {
            break
        }
        read_pending Future<Result<u8, nil>> = @next(input)
        item Result<u8, nil> = @await(read_pending)
        if @is(item, Ok) {
            value u8 = item
            write_pending Future<Result<nil, StreamError>> = writer(value)
            write_result Result<nil, StreamError> = @await(write_pending)
            _ = write_result
            remaining = @sub(remaining, 1)
        } else {
            break
        }
    }
    @cancel(source_done)
    pending Future<Result<nil, ProbeError>> = sink_write(writer)
    return @await(pending)
}
