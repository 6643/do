wait_until = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)

run(when u64) -> nil {
    pending Future<nil> = wait_until(when)
    @await(pending)
}

start() {}
