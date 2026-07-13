sum = @host("env", "sum", (i32, i32) -> i32)

test "spread host import fixed target" {
    values [i32] = .{1, 2}
    x = sum(...values)
    return
}
