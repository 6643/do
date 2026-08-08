host_input_read = @host_func("wasi:io/streams@0.3.0", "input-stream.read", (input-stream, u64) -> Result<[u8], StreamError>)

StreamError error = StreamClosed

start() {
    data [u8] = .{}
    status i32 = 0
    data, status = host_input_read(1, 16)
    return
}
