JsonError error = Bad

Box {
    value i32
}

emit(value text, depth usize) -> text | JsonError {
    return value
}

#T
emit(value T | nil, depth usize) -> text | JsonError {
    if @eq(value, nil) return "null"
    return emit(value, depth)
}

#T
emit(value T, depth usize) -> text | JsonError {
    loop field = fields(T) {
        return "box"
    }
    return Bad
}

start() {
    value text | nil = "amy"
    _ = emit(value, 1)
    return
}
