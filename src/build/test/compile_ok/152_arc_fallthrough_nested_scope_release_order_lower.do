start() {
    if @eq(1, 1) {
        outer [u8] = "outer"
        if @eq(1, 1) {
            inner [u8] = "inner"
        }
    }
    return
}
