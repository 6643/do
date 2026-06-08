host_output_write = @wasi("io/streams/output-stream.write", (output-stream, list<u8>) -> result<_,stream-error>)
host_output_flush = @wasi("io/streams/output-stream.flush", (output-stream) -> result<_,stream-error>)

start() {
    data [u8] = "abc"
    status i32 = 0
    _, status = host_output_write(1, data)
    _, status = host_output_flush(1)
    return
}
