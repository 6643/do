test "upper loop bind" {
    xs [i32] = .{1}
    loop Value, i = xs {
        return
    }
}
