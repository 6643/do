LoadError error = Bad

maybe(data [u8], ok bool) -> [u8] | LoadError | nil {
    if ok return data
    return nil
}

test "compiled union nil expr call last use move" {
    data [u8] = .{1, 2, 3}
    if @eq(maybe(data, false), nil) return
}
