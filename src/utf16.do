Utf16Error error = Utf16UnexpectedEnd | Utf16UnpairedSurrogate | Utf16OutOfRange

Utf16Decode {
    code u32
    size usize
}

.is_high_surrogate(unit u16) -> bool {
    return @and(@ge(unit, 55296), @le(unit, 56319))
}

.is_low_surrogate(unit u16) -> bool {
    return @and(@ge(unit, 56320), @le(unit, 57343))
}

decode_at(units [u16], offset usize) -> Utf16Decode | Utf16Error {
    if @ge(offset, @len(units)) return Utf16UnexpectedEnd

    u0 u16 = @get(units, offset)
    if is_high_surrogate(u0) {
        if @ge(@add(offset, 1), @len(units)) return Utf16UnexpectedEnd
        u1 u16 = @get(units, @add(offset, 1))
        if @not(is_low_surrogate(u1)) return Utf16UnpairedSurrogate
        code u32 = @add(65536, @mul(@to_u32(@sub(u0, 55296)), 1024), @to_u32(@sub(u1, 56320)))
        return Utf16Decode{code = code, size = 2}
    }

    if is_low_surrogate(u0) return Utf16UnpairedSurrogate

    return Utf16Decode{code = @to_u32(u0), size = 1}
}

code_at(units [u16], offset usize) -> u32 | Utf16Error {
    d = decode_at(units, offset)
    if @is(d, Utf16Error) return d
    return @get(d, .code)
}

size_at(units [u16], offset usize) -> usize | Utf16Error {
    d = decode_at(units, offset)
    if @is(d, Utf16Error) return d
    return @get(d, .size)
}

encode(code u32) -> [u16] | Utf16Error {
    if @gt(code, 1114111) return Utf16OutOfRange
    if @and(@ge(code, 55296), @le(code, 57343)) return Utf16UnpairedSurrogate
    if @le(code, 65535) return @put(.{}, @to_u16(code))

    n u32 = @sub(code, 65536)
    out [u16] = .{}
    out = @put(out, @to_u16(@add(55296, @div(n, 1024))))
    out = @put(out, @to_u16(@add(56320, @rem(n, 1024))))
    return out
}

validate(units [u16]) -> Utf16Error | nil {
    i usize = 0
    loop {
        if @ge(i, @len(units)) return nil
        d = decode_at(units, i)
        if @is(d, Utf16Error) return d
        i = @add(i, @get(d, .size))
    }
}

is_valid(units [u16]) -> bool {
    return @eq(validate(units), nil)
}

count(units [u16]) -> usize | Utf16Error {
    out usize = 0
    i usize = 0
    loop {
        if @ge(i, @len(units)) return out
        d = decode_at(units, i)
        if @is(d, Utf16Error) return d
        i = @add(i, @get(d, .size))
        out = @add(out, 1)
    }
}
