unix_ms = @lib("time.do", unix_ms)

start() {
    now i64 = unix_ms()
    return
}
