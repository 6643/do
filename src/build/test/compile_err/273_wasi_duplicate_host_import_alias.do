host_now = @wasi("random/random/get-random-u64", () -> u64)
host_now = @wasi("clocks/system-clock/get-resolution", () -> u64)

start() {
    return
}
