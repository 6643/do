test "defer block continue" {
    loop {
        defer {
            continue
        }
        break
    }
    return
}
