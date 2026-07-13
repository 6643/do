host_now = @host("wasi:clocks/system-clock@0.3.0", "now", () -> u64)

test "wasi known signature mismatch" {
    return
}
