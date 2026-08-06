clock_wait = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

run(duration u64) -> nil {
    waiting Future<nil> = clock_wait(duration)
    @await(waiting)
}

start() {}
