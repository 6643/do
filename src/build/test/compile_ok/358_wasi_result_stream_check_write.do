.host_output_check_write = @host_func("wasi:io/streams@0.3.0", "output-stream.check-write", (OutputStream) -> Result<u64, StreamError>)
OutputStream = @wasi_resource("io/streams/output-stream", {
    .id i64
})
StreamError error = StreamClosed | StreamCheckWriteFailed

start() {
    output OutputStream = OutputStream{id = 1}
    checked Result<u64, StreamError> = host_output_check_write(output)
    if @is(checked, Ok) {
        allowed u64 = checked
    }
}
