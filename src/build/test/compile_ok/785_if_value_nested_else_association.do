start() {
    outer bool = true
    inner bool = false
    value i32 = if outer if inner 1 else 2 else 3
    _ = value
    return
}
