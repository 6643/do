test "defer block break" {
    loop {
        defer {
            break
        }
        break
    }
    return
}
