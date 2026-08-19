test "compiled f64 list update preserves old value" {
    input [f64] = .{1.5, 2.25, 4.75}
    updated [f64] = @set(input, 1, 3.5)
    old f64 = @get(input, 1)
    next f64 = @get(updated, 1)
    if @and(@eq(old, 2.25), @eq(next, 3.5)) return
}
