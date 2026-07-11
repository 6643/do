test "compiled tuple path chain get" {
    items [Tuple<i32, u8>] = .{Tuple<i32, u8>{11, 22}}
    a i32 = @get(items, 0, 0)
    b u8 = @get(items, 0, 1)
    if @and(@eq(a, 11), @eq(b, 22)) return
}
