test "scalar storage variadic put preserves values" {
    i8s [i8] = .{1}
    i8s = @put(i8s, 2, 3)
    i16s [i16] = .{1}
    i16s = @put(i16s, 2, 3)
    i32s [i32] = .{1}
    i32s = @put(i32s, 2, 3)
    i64s [i64] = .{1}
    i64s = @put(i64s, 2, 3)
    u16s [u16] = .{1}
    u16s = @put(u16s, 2, 3)
    u32s [u32] = .{1}
    u32s = @put(u32s, 2, 3)
    u64s [u64] = .{1}
    u64s = @put(u64s, 2, 3)
    isizes [isize] = .{1}
    isizes = @put(isizes, 2, 3)
    usizes [usize] = .{1}
    usizes = @put(usizes, 2, 3)
    f32s [f32] = .{1.0}
    f32s = @put(f32s, 2.0, 3.0)
    f64s [f64] = .{1.0}
    f64s = @put(f64s, 2.0, 3.0)
    flags [bool] = .{true}
    flags = @put(flags, false, true)

    ok bool = true
    ok = @and(ok, @eq(@len(i8s), 3))
    ok = @and(ok, @eq(@get(i8s, 2), 3))
    ok = @and(ok, @eq(@len(i16s), 3))
    ok = @and(ok, @eq(@get(i16s, 2), 3))
    ok = @and(ok, @eq(@len(i32s), 3))
    ok = @and(ok, @eq(@get(i32s, 2), 3))
    ok = @and(ok, @eq(@len(i64s), 3))
    ok = @and(ok, @eq(@get(i64s, 2), 3))
    ok = @and(ok, @eq(@len(u16s), 3))
    ok = @and(ok, @eq(@get(u16s, 2), 3))
    ok = @and(ok, @eq(@len(u32s), 3))
    ok = @and(ok, @eq(@get(u32s, 2), 3))
    ok = @and(ok, @eq(@len(u64s), 3))
    ok = @and(ok, @eq(@get(u64s, 2), 3))
    ok = @and(ok, @eq(@len(isizes), 3))
    ok = @and(ok, @eq(@get(isizes, 2), 3))
    ok = @and(ok, @eq(@len(usizes), 3))
    ok = @and(ok, @eq(@get(usizes, 2), 3))
    ok = @and(ok, @eq(@len(f32s), 3))
    ok = @and(ok, @eq(@get(f32s, 2), 3.0))
    ok = @and(ok, @eq(@len(f64s), 3))
    ok = @and(ok, @eq(@get(f64s, 2), 3.0))
    ok = @and(ok, @eq(@len(flags), 3))
    ok = @and(ok, @eq(@get(flags, 0), true))
    ok = @and(ok, @eq(@get(flags, 1), false))
    ok = @and(ok, @eq(@get(flags, 2), true))
    if ok return
    return
}
