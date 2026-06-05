math_abs_i16 = @math.do/abs_i16
math_abs_i8 = @math.do/abs_i8
math_clamp_i16 = @math.do/clamp_i16
math_clamp_i8 = @math.do/clamp_i8
math_clamp_u16 = @math.do/clamp_u16
math_clamp_u8 = @math.do/clamp_u8
math_max_i16 = @math.do/max_i16
math_max_i8 = @math.do/max_i8
math_max_u16 = @math.do/max_u16
math_max_u8 = @math.do/max_u8
math_min_i16 = @math.do/min_i16
math_min_i8 = @math.do/min_i8
math_min_u16 = @math.do/min_u16
math_min_u8 = @math.do/min_u8

test "math small int helpers" {
    ok bool = true
    ok = and(ok, eq(math_min_i8(-4, 7), -4))
    ok = and(ok, eq(math_max_i8(-4, 7), 7))
    ok = and(ok, eq(math_clamp_i8(12, -5, 9), 9))
    ok = and(ok, eq(math_abs_i8(-8), 8))
    ok = and(ok, eq(math_min_i16(-40, 70), -40))
    ok = and(ok, eq(math_max_i16(-40, 70), 70))
    ok = and(ok, eq(math_clamp_i16(-12, -5, 9), -5))
    ok = and(ok, eq(math_abs_i16(-80), 80))
    ok = and(ok, eq(math_min_u8(4, 7), 4))
    ok = and(ok, eq(math_max_u8(4, 7), 7))
    ok = and(ok, eq(math_clamp_u8(12, 1, 9), 9))
    ok = and(ok, eq(math_min_u16(40, 70), 40))
    ok = and(ok, eq(math_max_u16(40, 70), 70))
    ok = and(ok, eq(math_clamp_u16(0, 5, 9), 5))
    if ok return
}
