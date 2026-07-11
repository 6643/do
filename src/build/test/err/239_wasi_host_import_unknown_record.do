host_now = @wasi("clocks/system-clock/now", () -> Datetime)

test "wasi host import unknown record" {}
