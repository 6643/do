wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

run(how_long u64) -> nil {
    pending Future<nil> = wait_for(how_long)
    @await(pending)
    return
}

start() {}
