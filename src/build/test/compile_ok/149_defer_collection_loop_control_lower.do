cleanup() -> nil {
    return
}

start() {
    xs [i32] = .{1, 2}
    loop value, index = xs {
        tmp [u8] = "tmp"
        defer cleanup()
        if @eq(index, 0) continue
        break
    }
    return
}
