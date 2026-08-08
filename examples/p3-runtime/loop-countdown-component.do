wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

run(input u64) -> nil {
    remaining u64 = 2
    loop {
        pending Future<nil> = wait_for(input)
        @await(pending)
        remaining = @sub(remaining, 1)
        if @eq(remaining, 0) {
            break
        }
    }
    return
}

start() {}
