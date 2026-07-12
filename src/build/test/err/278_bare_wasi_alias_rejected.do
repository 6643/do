host_res = @wasi("clocks/system-clock/get-resolution", () -> u64)
start() {
    _ = host_res()
}
