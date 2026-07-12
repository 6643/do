host_input_read = @wasi_func("io/streams/input-stream.read", (input-stream, u64) -> result<list<u8>,stream-error>)

start() {
    data [u8] = .{}
    status i32 = 0
    data, status = host_input_read(1, 16)
    return
}
