start() {
    cond bool = true
    value i32 = if cond {
        branch_local i32 = 17
        branch_local
    } else 9

    escaped i32 = branch_local
    _ = value
    _ = escaped
    return
}
