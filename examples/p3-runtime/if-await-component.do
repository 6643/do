wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)
wait_until = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-until", (u64) -> nil)

async run(input u64) -> nil {
    if @eq(input, 27815) {
        first Future<nil> = wait_for(input)
        await(first)
        return
    } else {
        second Future<nil> = wait_until(input)
        await(second)
        return
    }
}

start() {}
