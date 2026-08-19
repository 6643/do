test "compiled u32 list update preserves old value" {
    original [u32] = .{7, 12, 17}
    updated [u32] = @set(original, 1, 65)
    ok bool = @and(@eq(@get(original, 1), 12), @eq(@get(updated, 1), 65))
    if ok return
}
