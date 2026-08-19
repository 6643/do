append(rows [[u8]], row [u8]) -> [[u8]] {
    return @put(rows, row)
}

start() {}

test "nested byte-list put preserves source and appends row" {
    first [u8] = .{1, 2, 3}
    rows [[u8]] = .{first}
    second [u8] = .{4, 5}
    result [[u8]] = @put(rows, second)
    if @eq(@len(rows), 1) {
        if @eq(@len(result), 2) {
            if @eq(@len(@get(result, 1)), 2) return
        }
    }
}
