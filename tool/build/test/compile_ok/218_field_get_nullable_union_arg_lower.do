User {
    name text | nil
}

emit_text(value text | nil) -> text {
    if @eq(value, nil) return "null"
    return value
}

#T
walk(value T) -> text {
    loop field = fields(T) {
        return emit_text(@field_get(value, field))
    }
    return "empty"
}

start() {
    user User = User{name = nil}
    _ = walk(user)
    return
}
