.host_input_read = @host_func("wasi:io/streams@0.3.0", "input-stream.read", (InputStream, u64) -> Result<[u8], StreamError>)
InputStream = @wasi_resource("io/streams/input-stream", {
    .id i64
})
StreamError error = StreamClosed | StreamReadFailed

start() {
    input InputStream = InputStream{id = 1}
    read Result<[u8], StreamError> = host_input_read(input, 64)
    if @is(read, Err) {
        failure StreamError = read
    }
}
