cleanup() {
    return
}

test "defer block return" {
    defer {
        return
    }
    return
}
