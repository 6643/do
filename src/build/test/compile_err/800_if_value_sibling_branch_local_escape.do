start() {
    cond bool = true
    value i32 = if cond {
        branch_local i32 = 17
        branch_local
    } else branch_local
    _ = value
    return
}
