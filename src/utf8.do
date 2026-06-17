Utf8Error error = Utf8UnexpectedEnd | Utf8InvalidStart | Utf8InvalidContinuation | Utf8Overlong | Utf8Surrogate | Utf8OutOfRange

Utf8Decode {
    code u32
    size usize
}

.is_continuation(b u8) -> bool {
    return @and(@ge(b, 128), @le(b, 191))
}

.need(bytes [u8], offset usize, size usize) -> Utf8Error | nil {
    if @gt(@add(offset, size), @len(bytes)) return Utf8UnexpectedEnd
    return nil
}

decode_at(bytes [u8], offset usize) -> Utf8Decode | Utf8Error {
    if @ge(offset, @len(bytes)) return Utf8UnexpectedEnd

    b0 u8 = @get(bytes, offset)
    if @le(b0, 127) {
        return Utf8Decode{code = @as(u32, b0), size = 1}
    }

    if @lt(b0, 194) return Utf8InvalidStart

    if @le(b0, 223) {
        err = need(bytes, offset, 2)
        if @is(err, Utf8Error) return err
        b1 u8 = @get(bytes, @add(offset, 1))
        if @not(is_continuation(b1)) return Utf8InvalidContinuation
        return Utf8Decode{code = @add(@mul(@as(u32, @sub(b0, 192)), 64), @as(u32, @sub(b1, 128))), size = 2}
    }

    if @le(b0, 239) {
        err = need(bytes, offset, 3)
        if @is(err, Utf8Error) return err
        b1 u8 = @get(bytes, @add(offset, 1))
        b2 u8 = @get(bytes, @add(offset, 2))
        if @not(is_continuation(b1)) return Utf8InvalidContinuation
        if @not(is_continuation(b2)) return Utf8InvalidContinuation
        if @and(@eq(b0, 224), @lt(b1, 160)) return Utf8Overlong
        if @and(@eq(b0, 237), @gt(b1, 159)) return Utf8Surrogate
        code u32 = @add(@mul(@as(u32, @sub(b0, 224)), 4096), @mul(@as(u32, @sub(b1, 128)), 64), @as(u32, @sub(b2, 128)))
        return Utf8Decode{code = code, size = 3}
    }

    if @le(b0, 244) {
        err = need(bytes, offset, 4)
        if @is(err, Utf8Error) return err
        b1 u8 = @get(bytes, @add(offset, 1))
        b2 u8 = @get(bytes, @add(offset, 2))
        b3 u8 = @get(bytes, @add(offset, 3))
        if @not(is_continuation(b1)) return Utf8InvalidContinuation
        if @not(is_continuation(b2)) return Utf8InvalidContinuation
        if @not(is_continuation(b3)) return Utf8InvalidContinuation
        if @and(@eq(b0, 240), @lt(b1, 144)) return Utf8Overlong
        if @and(@eq(b0, 244), @gt(b1, 143)) return Utf8OutOfRange
        code u32 = @add(@mul(@as(u32, @sub(b0, 240)), 262144), @mul(@as(u32, @sub(b1, 128)), 4096), @mul(@as(u32, @sub(b2, 128)), 64), @as(u32, @sub(b3, 128)))
        return Utf8Decode{code = code, size = 4}
    }

    return Utf8InvalidStart
}

code_at(bytes [u8], offset usize) -> u32 | Utf8Error {
    d = decode_at(bytes, offset)
    if @is(d, Utf8Error) return d
    return @get(d, .code)
}

size_at(bytes [u8], offset usize) -> usize | Utf8Error {
    d = decode_at(bytes, offset)
    if @is(d, Utf8Error) return d
    return @get(d, .size)
}

encode(code u32) -> [u8] | Utf8Error {
    if @le(code, 127) return @put(.{}, @as(u8, code))
    if @le(code, 2047) {
        out [u8] = .{}
        out = @put(out, @as(u8, @add(192, @div(code, 64))))
        out = @put(out, @as(u8, @add(128, @rem(code, 64))))
        return out
    }
    if @and(@ge(code, 55296), @le(code, 57343)) return Utf8Surrogate
    if @le(code, 65535) {
        out [u8] = .{}
        out = @put(out, @as(u8, @add(224, @div(code, 4096))))
        out = @put(out, @as(u8, @add(128, @rem(@div(code, 64), 64))))
        out = @put(out, @as(u8, @add(128, @rem(code, 64))))
        return out
    }
    if @le(code, 1114111) {
        out [u8] = .{}
        out = @put(out, @as(u8, @add(240, @div(code, 262144))))
        out = @put(out, @as(u8, @add(128, @rem(@div(code, 4096), 64))))
        out = @put(out, @as(u8, @add(128, @rem(@div(code, 64), 64))))
        out = @put(out, @as(u8, @add(128, @rem(code, 64))))
        return out
    }
    return Utf8OutOfRange
}

validate(bytes [u8]) -> Utf8Error | nil {
    i usize = 0
    loop {
        if @ge(i, @len(bytes)) return nil
        d = decode_at(bytes, i)
        if @is(d, Utf8Error) return d
        i = @add(i, @get(d, .size))
    }
}

is_valid(bytes [u8]) -> bool {
    return @eq(validate(bytes), nil)
}

count(bytes [u8]) -> usize | Utf8Error {
    out usize = 0
    i usize = 0
    loop {
        if @ge(i, @len(bytes)) return out
        d = decode_at(bytes, i)
        if @is(d, Utf8Error) return d
        i = @add(i, @get(d, .size))
        out = @add(out, 1)
    }
}
