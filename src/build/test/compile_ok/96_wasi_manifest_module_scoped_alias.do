unix_ms = @lib("time.do", unix_ms)

host_now = @host("wasi:random/random@0.3.0", "get-random-u64", () -> u64)

start() {
    return
}
