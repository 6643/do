host_output_check_write = @wasi_func("io/streams/output-stream.check-write", (output-stream) -> result<u64,stream-error>)

start() {
    allowed u64 = 0
    status i32 = 0
    allowed, status = host_output_check_write(1)
    return
}
