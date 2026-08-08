host_now = @host_func("wasi:clocks/system-clock@0.3.0", "now", () -> Datetime)

Datetime {
    seconds i64
    nanos u32
}

test "wasi known record mismatch" {
    return
}
