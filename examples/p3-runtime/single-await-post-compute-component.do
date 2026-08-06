wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

run(input u64) -> nil {
    deadline u64 = @add(input, 1)
    pending Future<nil> = wait_for(deadline)
    @await(pending)
    after u64 = @add(deadline, 1)
    _ = after
    return
}

start() {}
