math_bit_at_u32 = @lib("math.do", bit_at_u32)
math_bit_not_u32 = @lib("math.do", bit_not_u32)
math_clamp_i16 = @lib("math.do", clamp_i16)
math_clamp_i8 = @lib("math.do", clamp_i8)
math_clamp_u16 = @lib("math.do", clamp_u16)
math_clamp_u8 = @lib("math.do", clamp_u8)

test "math small int helpers" {
    ok bool = true
    ok = @and(ok, @eq(math_bit_at_u32(10, 0), 0))
    ok = @and(ok, @eq(math_bit_at_u32(10, 1), 1))
    ok = @and(ok, @eq(math_bit_not_u32(0), 4294967295))
    ok = @and(ok, @eq(math_clamp_i8(12, -5, 9), 9))
    ok = @and(ok, @eq(math_clamp_i16(-12, -5, 9), -5))
    ok = @and(ok, @eq(math_clamp_u8(12, 1, 9), 9))
    ok = @and(ok, @eq(math_clamp_u16(0, 5, 9), 5))
    if ok return
}
