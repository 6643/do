test "compiled i16 list update preserves old value" {
    original [i16] = .{7, 12, 17}
    updated [i16] = @set(original, 1, 65)
    ok bool = @and(@eq(@get(original, 1), 12), @eq(@get(updated, 1), 65))
    if ok return
}
