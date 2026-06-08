Datetime {
    seconds i64
    nanos u32
}

host_now = @wasi("clocks/system-clock/now", () -> Datetime)

test "wasi known record mismatch" {
    return
}
