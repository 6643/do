host_now = @host("wasi:clocks/system-clock@0.3.0", "now", () -> Datetime)

test "wasi host import unknown record" {}
