start() {
    cond bool = true
    pair Tuple<i32, bool> = if cond .{1, true} else .{2, false}
    pair = if cond .{3, false}
    _ = pair
    return
}
