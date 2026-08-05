wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

async run(how_long u64) -> nil {
    pending Future<nil> = wait_for(how_long)
    @cancel(pending)
}

start() {}
