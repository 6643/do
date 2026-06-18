emit_text(value text | nil) -> text {
    if @eq(value, nil) return "null"
    return value
}

start() {
    value text | nil = nil
    _ = emit_text(value)
    return
}
