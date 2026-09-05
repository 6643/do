wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

ready() -> i32 {
    return 1
}

run() -> nil {
    pending Future<i32> = @async(ready())
    value i32 = @await(pending)
    _ = value
}

start() {}
