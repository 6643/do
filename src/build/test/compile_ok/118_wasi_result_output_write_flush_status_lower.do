// output write/flush: exclusive union nil|i32; multi-lhs status binding remains lowerable.
host_output_write = @host("wasi:io/streams@0.3.0", "output-stream.write", (i32, [u8]) -> nil | i32)
host_output_flush = @host("wasi:io/streams@0.3.0", "output-stream.flush", (i32) -> nil | i32)

start() {
    data [u8] = "abc"
    status i32 = 0
    _, status = host_output_write(1, data)
    _, status = host_output_flush(1)
    return
}
