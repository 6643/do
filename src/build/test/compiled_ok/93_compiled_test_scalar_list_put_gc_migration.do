test "compiled scalar list put preserves source values" {
    u32_input [u32] = .{1, 2, 3}
    u32_updated [u32] = @put(u32_input, 65)
    f64_input [f64] = .{1.0, 2.0, 3.0}
    f64_updated [f64] = @put(f64_input, 65.0)

    ok bool = true
    ok = @and(ok, @eq(@len(u32_input), 3))
    ok = @and(ok, @eq(@len(u32_updated), 4))
    ok = @and(ok, @eq(@get(u32_input, 2), 3))
    ok = @and(ok, @eq(@get(u32_updated, 3), 65))
    ok = @and(ok, @eq(@len(f64_input), 3))
    ok = @and(ok, @eq(@len(f64_updated), 4))
    ok = @and(ok, @eq(@get(f64_input, 2), 3.0))
    ok = @and(ok, @eq(@get(f64_updated, 3), 65.0))
    if ok return
}
