start() {
    items [Tuple<i32, u8>] = .{Tuple<i32, u8>{1, 2}}
    a i32 = @get(items, 0, 0)
    b u8 = @get(items, 0, 1)
    _ = a
    _ = b
}
