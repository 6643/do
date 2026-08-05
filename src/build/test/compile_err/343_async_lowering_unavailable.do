wait_for = @host_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

async ready() -> i32 {
    return 1
}

start() {}
