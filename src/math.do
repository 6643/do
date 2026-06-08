_i8_max i8 = 127
_i8_min i8 = -128
_i16_max i16 = 32767
_i16_min i16 = -32768
_i32_max i32 = 2147483647
_i32_min i32 = -2147483648
_i64_max i64 = 9223372036854775807
_i64_min i64 = -9223372036854775808
_isize_max isize = 2147483647
_isize_min isize = -2147483648
_u8_min u8 = 0
_u8_max u8 = 255
_u16_min u16 = 0
_u16_max u16 = 65535
_u32_min u32 = 0
_u32_max u32 = 4294967295
_u64_min u64 = 0
_u64_max u64 = 18446744073709551615
_usize_min usize = 0
_usize_max usize = 4294967295
_f32_e f32 = 2.7182817
_f32_pi f32 = 3.1415927
_f32_half_pi f32 = 1.5707964
_f32_tau f32 = 6.2831855
_f32_sqrt2 f32 = 1.4142135
_f64_e f64 = 2.718281828459045
_f64_pi f64 = 3.141592653589793
_f64_half_pi f64 = 1.5707963267948966
_f64_tau f64 = 6.283185307179586
_f64_sqrt2 f64 = 1.4142135623730951

pow2_u32(exp usize) -> u32 {
    value u32 = 1
    i usize = 0
    loop {
        if @eq(i, exp) return value
        value = mul_wrap_u32(value, 2)
        i = @add(i, 1)
    }
}

wrap_u32(x u64) -> u32 {
    return @to_u32(@rem(x, 4294967296))
}

add_wrap_u32(a u32, b u32) -> u32 {
    return wrap_u32(@add(@to_u64(a), @to_u64(b)))
}

mul_wrap_u32(a u32, b u32) -> u32 {
    return wrap_u32(@mul(@to_u64(a), @to_u64(b)))
}

bit_at_u32(value u32, index usize) -> u32 {
    if @ge(index, 32) return 0
    base u32 = pow2_u32(index)
    return @rem(@div(value, base), 2)
}

bit_not_u32(value u32) -> u32 {
    return @xor(value, _u32_max)
}

clamp_i8(value i8, low i8, high i8) -> i8 {
    if @lt(value, low) return low
    if @gt(value, high) return high
    return value
}

clamp_i16(value i16, low i16, high i16) -> i16 {
    if @lt(value, low) return low
    if @gt(value, high) return high
    return value
}

clamp_i32(value i32, low i32, high i32) -> i32 {
    if @lt(value, low) return low
    if @gt(value, high) return high
    return value
}

clamp_i64(value i64, low i64, high i64) -> i64 {
    if @lt(value, low) return low
    if @gt(value, high) return high
    return value
}

clamp_isize(value isize, low isize, high isize) -> isize {
    if @lt(value, low) return low
    if @gt(value, high) return high
    return value
}

clamp_u8(value u8, low u8, high u8) -> u8 {
    if @lt(value, low) return low
    if @gt(value, high) return high
    return value
}

clamp_u16(value u16, low u16, high u16) -> u16 {
    if @lt(value, low) return low
    if @gt(value, high) return high
    return value
}

clamp_u32(value u32, low u32, high u32) -> u32 {
    if @lt(value, low) return low
    if @gt(value, high) return high
    return value
}

clamp_u64(value u64, low u64, high u64) -> u64 {
    if @lt(value, low) return low
    if @gt(value, high) return high
    return value
}

clamp_usize(value usize, low usize, high usize) -> usize {
    if @lt(value, low) return low
    if @gt(value, high) return high
    return value
}

add_saturating_u32(a u32, b u32) -> u32 {
    if @gt(a, @sub(_u32_max, b)) return _u32_max
    return @add(a, b)
}

sub_saturating_u32(a u32, b u32) -> u32 {
    if @lt(a, b) return 0
    return @sub(a, b)
}

mul_saturating_u32(a u32, b u32) -> u32 {
    if @eq(a, 0) return 0
    if @eq(b, 0) return 0
    limit u32 = @div(_u32_max, b)
    if @gt(a, limit) return _u32_max
    return @mul(a, b)
}

add_checked_u32(a u32, b u32, fallback u32) -> u32, bool {
    if @gt(a, @sub(_u32_max, b)) return fallback, false
    return @add(a, b), true
}

mul_checked_u32(a u32, b u32, fallback u32) -> u32, bool {
    if @eq(a, 0) return 0, true
    if @eq(b, 0) return 0, true
    limit u32 = @div(_u32_max, b)
    if @gt(a, limit) return fallback, false
    return @mul(a, b), true
}
