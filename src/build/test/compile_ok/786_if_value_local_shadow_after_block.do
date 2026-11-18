print_i(value i32) -> nil { return }
start() {
    cond bool = true
    value i32 = if cond {
        branch_local i32 = 17
        branch_local
    } else 9
    if cond {
        branch_local i32 = 22
        print_i(branch_local)
    }
    _ = value
    return
}
