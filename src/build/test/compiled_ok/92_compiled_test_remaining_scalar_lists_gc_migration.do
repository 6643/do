test "compiled remaining scalar list updates preserve old values" {
    i8_old [i8] = .{7, 12, 17}
    i8_new [i8] = @set(i8_old, 1, 65)
    u16_old [u16] = .{7, 12, 17}
    u16_new [u16] = @set(u16_old, 1, 65)
    u64_old [u64] = .{7, 12, 17}
    u64_new [u64] = @set(u64_old, 1, 65)
    isize_old [isize] = .{7, 12, 17}
    isize_new [isize] = @set(isize_old, 1, 65)
    usize_old [usize] = .{7, 12, 17}
    usize_new [usize] = @set(usize_old, 1, 65)

    ok bool = true
    ok = @and(ok, @eq(@get(i8_old, 1), 12))
    ok = @and(ok, @eq(@get(i8_new, 1), 65))
    ok = @and(ok, @eq(@get(u16_old, 1), 12))
    ok = @and(ok, @eq(@get(u16_new, 1), 65))
    ok = @and(ok, @eq(@get(u64_old, 1), 12))
    ok = @and(ok, @eq(@get(u64_new, 1), 65))
    ok = @and(ok, @eq(@get(isize_old, 1), 12))
    ok = @and(ok, @eq(@get(isize_new, 1), 65))
    ok = @and(ok, @eq(@get(usize_old, 1), 12))
    ok = @and(ok, @eq(@get(usize_new, 1), 65))
    if ok return
}
