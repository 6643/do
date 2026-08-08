wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)

start() {}
