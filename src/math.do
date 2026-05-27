_i8_max i8 = 127
_i8_min i8 = -128
_u8_max u8 = 255
_u16_max u16 = 65535
_u32_max u32 = 4294967295
_u64_max u64 = 18446744073709551615
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
