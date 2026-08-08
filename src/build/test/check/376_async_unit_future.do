wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

run(how_long u64) -> nil {
    delay u64 = @add(how_long, 41)
    pending Future<nil> = wait_for(delay)
    @await(pending)
}

start() {}
