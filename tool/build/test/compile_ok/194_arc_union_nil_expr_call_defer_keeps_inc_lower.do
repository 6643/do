nop() -> nil {
    return nil
}

LoadError error = Bad

maybe(data [u8], ok bool) -> [u8] | LoadError | nil {
    if ok return data
    return nil
}

start() {
    data [u8] = "abc"
    defer nop()
    if @eq(maybe(data, false), nil) return
    return
}
