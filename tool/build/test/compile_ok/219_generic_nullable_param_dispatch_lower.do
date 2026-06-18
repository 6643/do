emit(value text, depth usize) -> text {
    return value
}

#T
emit(value T | nil, depth usize) -> text {
    if @eq(value, nil) return "null"
    return emit(value, depth)
}

start() {
    value text | nil = "amy"
    _ = emit(value, 1)
    return
}
