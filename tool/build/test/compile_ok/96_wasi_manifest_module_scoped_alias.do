unix_ms = @lib("time.do", unix_ms)

host_now = @wasi("random/random/get-random-u64", () -> u64)

start() {
    return
}
