_i8_max i8 = 127
_i8_min i8 = -128
_u8_max u8 = 255
_u16_max u16 = 65535
_u32_max u32 = 4294967295
_u64_max u64 = 18446744073709551615
_i32_max i32 = 2147483647
_i64_max i64 = 9223372036854775807
_f32_pi f32 = 3.1415927
_f64_pi f64 = 3.141592653589793

pow2_u32(exp usize) -> u32 {
    value u32 = 1
    i usize = 0
    loop {
        if eq(i, exp) return value
        value = mul_wrap_u32(value, 2)
        i = add(i, 1)
    }
}

wrap_u32(x u64) -> u32 {
    return to_u32(rem(x, 4294967296))
}

add_wrap_u32(a u32, b u32) -> u32 {
    return wrap_u32(add(to_u64(a), to_u64(b)))
}

mul_wrap_u32(a u32, b u32) -> u32 {
    return wrap_u32(mul(to_u64(a), to_u64(b)))
}

bit_at_u32(value u32, index usize) -> u32 {
    if ge(index, 32) return 0
    base u32 = pow2_u32(index)
    return rem(div(value, base), 2)
}

bit_not_u32(value u32) -> u32 {
    return sub(_u32_max, value)
}

bit_and_u32(a u32, b u32) -> u32 {
    out u32 = 0
    bit u32 = 1
    i usize = 0
    loop {
        if ge(i, 32) return out
        ai u32 = rem(div(a, bit), 2)
        bi u32 = rem(div(b, bit), 2)
        if and(eq(ai, 1), eq(bi, 1)) {
            out = add(out, bit)
        }
        bit = mul_wrap_u32(bit, 2)
        i = add(i, 1)
    }
}

bit_or_u32(a u32, b u32) -> u32 {
    out u32 = 0
    bit u32 = 1
    i usize = 0
    loop {
        if ge(i, 32) return out
        ai u32 = rem(div(a, bit), 2)
        bi u32 = rem(div(b, bit), 2)
        if or(eq(ai, 1), eq(bi, 1)) {
            out = add(out, bit)
        }
        bit = mul_wrap_u32(bit, 2)
        i = add(i, 1)
    }
}

bit_xor_u32(a u32, b u32) -> u32 {
    out u32 = 0
    bit u32 = 1
    i usize = 0
    loop {
        if ge(i, 32) return out
        ai u32 = rem(div(a, bit), 2)
        bi u32 = rem(div(b, bit), 2)
        if ne(ai, bi) {
            out = add(out, bit)
        }
        bit = mul_wrap_u32(bit, 2)
        i = add(i, 1)
    }
}

shl_u32(value u32, shift usize) -> u32 {
    if ge(shift, 32) return 0
    if eq(shift, 0) return value
    return mul_wrap_u32(value, pow2_u32(shift))
}

shr_u32(value u32, shift usize) -> u32 {
    if ge(shift, 32) return 0
    if eq(shift, 0) return value
    return div(value, pow2_u32(shift))
}

rotl_u32(value u32, shift usize) -> u32 {
    s usize = rem(shift, 32)
    if eq(s, 0) return value
    left u32 = shl_u32(value, s)
    right u32 = shr_u32(value, sub(32, s))
    return bit_or_u32(left, right)
}

rotr_u32(value u32, shift usize) -> u32 {
    s usize = rem(shift, 32)
    if eq(s, 0) return value
    right u32 = shr_u32(value, s)
    left u32 = shl_u32(value, sub(32, s))
    return bit_or_u32(left, right)
}

min_i8(a i8, b i8) -> i8 {
    if lt(a, b) return a
    return b
}

max_i8(a i8, b i8) -> i8 {
    if gt(a, b) return a
    return b
}

clamp_i8(value i8, low i8, high i8) -> i8 {
    if lt(value, low) return low
    if gt(value, high) return high
    return value
}

abs_i8(value i8) -> i8 {
    if lt(value, 0) return sub(0, value)
    return value
}

min_i16(a i16, b i16) -> i16 {
    if lt(a, b) return a
    return b
}

max_i16(a i16, b i16) -> i16 {
    if gt(a, b) return a
    return b
}

clamp_i16(value i16, low i16, high i16) -> i16 {
    if lt(value, low) return low
    if gt(value, high) return high
    return value
}

abs_i16(value i16) -> i16 {
    if lt(value, 0) return sub(0, value)
    return value
}

min_i32(a i32, b i32) -> i32 {
    if lt(a, b) return a
    return b
}

max_i32(a i32, b i32) -> i32 {
    if gt(a, b) return a
    return b
}

clamp_i32(value i32, low i32, high i32) -> i32 {
    if lt(value, low) return low
    if gt(value, high) return high
    return value
}

abs_i32(value i32) -> i32 {
    if lt(value, 0) return sub(0, value)
    return value
}

min_i64(a i64, b i64) -> i64 {
    if lt(a, b) return a
    return b
}

max_i64(a i64, b i64) -> i64 {
    if gt(a, b) return a
    return b
}

clamp_i64(value i64, low i64, high i64) -> i64 {
    if lt(value, low) return low
    if gt(value, high) return high
    return value
}

abs_i64(value i64) -> i64 {
    if lt(value, 0) return sub(0, value)
    return value
}

min_u8(a u8, b u8) -> u8 {
    if lt(a, b) return a
    return b
}

max_u8(a u8, b u8) -> u8 {
    if gt(a, b) return a
    return b
}

clamp_u8(value u8, low u8, high u8) -> u8 {
    if lt(value, low) return low
    if gt(value, high) return high
    return value
}

min_u16(a u16, b u16) -> u16 {
    if lt(a, b) return a
    return b
}

max_u16(a u16, b u16) -> u16 {
    if gt(a, b) return a
    return b
}

clamp_u16(value u16, low u16, high u16) -> u16 {
    if lt(value, low) return low
    if gt(value, high) return high
    return value
}

min_u32(a u32, b u32) -> u32 {
    if lt(a, b) return a
    return b
}

max_u32(a u32, b u32) -> u32 {
    if gt(a, b) return a
    return b
}

clamp_u32(value u32, low u32, high u32) -> u32 {
    if lt(value, low) return low
    if gt(value, high) return high
    return value
}

min_u64(a u64, b u64) -> u64 {
    if lt(a, b) return a
    return b
}

max_u64(a u64, b u64) -> u64 {
    if gt(a, b) return a
    return b
}

clamp_u64(value u64, low u64, high u64) -> u64 {
    if lt(value, low) return low
    if gt(value, high) return high
    return value
}

min_usize(a usize, b usize) -> usize {
    if lt(a, b) return a
    return b
}

max_usize(a usize, b usize) -> usize {
    if gt(a, b) return a
    return b
}

clamp_usize(value usize, low usize, high usize) -> usize {
    if lt(value, low) return low
    if gt(value, high) return high
    return value
}

add_saturating_u32(a u32, b u32) -> u32 {
    if gt(a, sub(_u32_max, b)) return _u32_max
    return add(a, b)
}

sub_saturating_u32(a u32, b u32) -> u32 {
    if lt(a, b) return 0
    return sub(a, b)
}

mul_saturating_u32(a u32, b u32) -> u32 {
    if eq(a, 0) return 0
    if eq(b, 0) return 0
    limit u32 = div(_u32_max, b)
    if gt(a, limit) return _u32_max
    return mul(a, b)
}

add_checked_u32(a u32, b u32, fallback u32) -> u32, bool {
    if gt(a, sub(_u32_max, b)) return fallback, false
    return add(a, b), true
}

mul_checked_u32(a u32, b u32, fallback u32) -> u32, bool {
    if eq(a, 0) return 0, true
    if eq(b, 0) return 0, true
    limit u32 = div(_u32_max, b)
    if gt(a, limit) return fallback, false
    return mul(a, b), true
}
