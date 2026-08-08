host_now = @host_func("wasi:random/random@0.3.0", "get-random-u64", () -> u64)
host_now = @host_func("wasi:clocks/system-clock@0.3.0", "get-resolution", () -> u64)

start() {
    return
}
