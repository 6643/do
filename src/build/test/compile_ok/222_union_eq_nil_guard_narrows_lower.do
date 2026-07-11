emit(value text | nil) -> text {
    if @eq(value, nil) return "null"
    return value
}

start() {
    value text | nil = "ok"
    out text = emit(value)
    return
}
