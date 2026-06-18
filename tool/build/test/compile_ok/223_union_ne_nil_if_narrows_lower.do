emit(value text | nil) -> text {
    if @ne(value, nil) {
        return value
    }
    return "null"
}

start() {
    value text | nil = "ok"
    out text = emit(value)
    return
}
