host_now = @wasi("clocks/system-clock/now", () -> u64)

test "wasi known signature mismatch" {
    return
}
