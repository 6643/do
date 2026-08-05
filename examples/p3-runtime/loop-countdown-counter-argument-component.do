wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

async run(input u64) -> nil {
    remaining u64 = input
    loop {
        pending Future<nil> = wait_for(remaining)
        await(pending)
        remaining = @sub(remaining, 1)
        if @eq(remaining, 0) {
            break
        }
    }
    return
}

start() {}
