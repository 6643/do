host_now = @wasi_func("clocks/system-clock/now", () -> u64)

test "wasi known signature mismatch" {
    return
}
