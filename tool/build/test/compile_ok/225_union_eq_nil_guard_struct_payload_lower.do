User {
    id i32
    name text
}

emit_user(user User) -> text {
    return @get(user, .name)
}

emit(value User | nil) -> text {
    if @eq(value, nil) return "null"
    return emit_user(value)
}

start() {
    user User = User{ id = 1, name = "amy" }
    value User | nil = user
    out text = emit(value)
    return
}
