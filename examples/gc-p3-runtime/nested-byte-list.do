make_nested() -> [[u8]] {
    first [u8] = .{1, 2, 3}
    nested [[u8]] = .{first}
    count i32 = @len(nested)
    row [u8] = @get(nested, 0)
    loop item, index = nested {
        size i32 = @len(item)
        if @eq(index, 0) break
    }
    return nested
}

start() {}
