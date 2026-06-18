collect(rest ...text | nil) -> [u8] {
    return "ok"
}

test "variadic union param" {
    value text | nil = nil
    _ = collect(value)
    return
}
