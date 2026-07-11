// Path chaining @get(storage, i, j) through Tuple storage element is post-I2.
start() {
    items [Tuple<i32, u8>] = .{Tuple<i32, u8>{1, 2}}
    a i32 = @get(items, 0, 0)
    _ = a
}
