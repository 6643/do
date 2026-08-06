wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
wait_until = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)

run(deadline u64) -> nil {
    first_deadline u64 = deadline
    first Future<nil> = wait_for(first_deadline)
    @await(first)
    second_deadline u64 = first_deadline
    second Future<nil> = wait_until(second_deadline)
    @await(second)
}

start() {}
