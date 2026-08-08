wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
wait_until = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)

run(input u64) -> nil {
    delay u64 = @add(input, 41)
    first Future<nil> = wait_for(delay)
    @await(first)
    second Future<nil> = wait_until(delay)
    @await(second)
}

start() {}
