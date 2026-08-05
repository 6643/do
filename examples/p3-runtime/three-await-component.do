wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
wait_until = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)

async run(deadline u64) -> nil {
    first Future<nil> = wait_for(deadline)
    await(first)
    second Future<nil> = wait_until(deadline)
    await(second)
    third Future<nil> = wait_for(deadline)
    await(third)
}

start() {}
