// check-write: exclusive union u64|i32 (ok = permit, err = status); multi-lhs remains lowerable.
host_output_check_write = @wasi_func("io/streams/output-stream.check-write", (i32) -> u64 | i32)

start() {
    allowed u64 = 0
    status i32 = 0
    allowed, status = host_output_check_write(1)
    return
}
