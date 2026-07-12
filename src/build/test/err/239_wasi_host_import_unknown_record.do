host_now = @wasi_func("clocks/system-clock/now", () -> Datetime)

test "wasi host import unknown record" {}
