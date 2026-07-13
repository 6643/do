host_input_read = @host("wasi:io/streams@0.3.0", "input-stream.read", (input-stream, u64) -> result<list<u8>,stream-error>)

start() {
    data [u8] = .{}
    status i32 = 0
    data, status = host_input_read(1, 16)
    return
}
