host_now = @wasi_func("clocks/system-clock/now", () -> Datetime)

Datetime {
    seconds i64
    nanos u32
}

test "wasi known record mismatch" {
    return
}
