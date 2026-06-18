JsonError error = Bad

emit(value text, depth usize) -> text | JsonError {
    return value
}

#T
emit(value T | nil, depth usize) -> text | JsonError {
    if @eq(value, nil) return "null"
    return emit(value, depth)
}

start() {
    value text | nil = "amy"
    _ = emit(value, 1)
    return
}
