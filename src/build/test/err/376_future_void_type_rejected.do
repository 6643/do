wait_for = @host_async_func("wasi:clocks@0.3.0", "monotonic-clock.wait-for", (u64) -> nil)

run(delay u64) -> nil {
    pending Future<void> = wait_for(delay)
    @await(pending)
}

test "void is not a do async value type" {}
