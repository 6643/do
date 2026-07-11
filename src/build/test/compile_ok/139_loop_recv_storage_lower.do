start() {
    ch [i32] = .{1, 2}
    loop value, count = recv(ch) {
        if @eq(count, 1) continue
        if @eq(value, 2) break
    }
    return
}
