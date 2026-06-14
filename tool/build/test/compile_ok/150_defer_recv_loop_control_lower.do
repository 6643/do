cleanup() -> nil {
    return
}

start() {
    xs [i32] = .{1, 2}
    loop value, count = recv(xs) {
        tmp [u8] = "tmp"
        defer cleanup()
        if @eq(count, 0) continue
        break
    }
    return
}
