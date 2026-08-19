test "compiled f32 list update preserves old value" {
    input [f32] = .{1.5, 2.25, 4.75}
    updated [f32] = @set(input, 1, 3.5)
    old f32 = @get(input, 1)
    next f32 = @get(updated, 1)
    if @and(@eq(old, 2.25), @eq(next, 3.5)) return
}
