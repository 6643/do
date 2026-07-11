pair() -> [i32], [i32] {
    left [i32] = .{1}
    right [i32] = .{2}
    return left, right
}

start() {
    a [i32] = .{}
    b [i32] = .{}
    a, b = pair()
    return
}
