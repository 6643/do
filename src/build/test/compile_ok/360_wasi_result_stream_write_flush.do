.host_output_write = @host("wasi:io/streams@0.3.0", "output-stream.write", (OutputStream, [u8]) -> Result<nil, StreamError>)
.host_output_flush = @host("wasi:io/streams@0.3.0", "output-stream.flush", (OutputStream) -> Result<nil, StreamError>)
OutputStream = @wasi_resource("io/streams/output-stream", {
    .id i64
})
StreamError error = StreamClosed | StreamWriteFailed | StreamFlushFailed

start() {
    output OutputStream = OutputStream{id = 1}
    data [u8] = .{}
    written Result<nil, StreamError> = host_output_write(output, data)
    if @is(written, Err) {
        write_failure StreamError = written
    }
    flushed Result<nil, StreamError> = host_output_flush(output)
    if @is(flushed, Err) {
        flush_failure StreamError = flushed
    }
}
