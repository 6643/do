host_now = @wasi_func("random/random/get-random-u64", () -> u64)
host_now = @wasi_func("clocks/system-clock/get-resolution", () -> u64)

start() {
    return
}
