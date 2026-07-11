test "tuple loop get index" {
    items [Tuple<i32, u8>] = .{Tuple<i32, u8>{1, 2}, Tuple<i32, u8>{3, 4}}
    sum i32 = 0
    loop v, i = items {
        sum = @add(sum, @get(v, 0))
        _ = i
    }
    if @eq(sum, 4) return
}
