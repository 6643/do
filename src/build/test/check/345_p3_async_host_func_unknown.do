wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.missing", (u64) -> nil)

start() {}
