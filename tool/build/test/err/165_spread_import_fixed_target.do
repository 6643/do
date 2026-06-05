only_one = @./fixture.arity_only_one.do/only_one

test "spread import fixed target" {
    values [i32] = .{1}
    x = only_one(...values)
    return
}
