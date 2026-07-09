BytesError error = BytesOutOfBounds | BytesInvalidRange

is_empty(xs [u8]) -> bool {
    return @eq(@len(xs), 0)
}

.append(out [u8], part [u8]) -> [u8] {
    next [u8] = out
    loop byte, _ = part {
        next = @put(next, byte)
    }
    return next
}

copy(xs [u8]) -> [u8] {
    return append(.{}, xs)
}

concat(a [u8], b [u8], rest ...[u8]) -> [u8] {
    out [u8] = append(.{}, a)
    out = append(out, b)
    loop chunk, _ = rest {
        out = append(out, chunk)
    }
    return out
}

repeat_byte(value u8, count usize) -> [u8] {
    out [u8] = .{}
    i usize = 0
    loop {
        if @ge(i, count) return out
        out = @put(out, value)
        i = @add(i, 1)
    }
}

slice(xs [u8], from usize, end usize) -> [u8] | BytesError {
    if @gt(from, end) return BytesInvalidRange
    if @gt(end, @len(xs)) return BytesOutOfBounds

    out [u8] = .{}
    i usize = from
    loop {
        if @ge(i, end) return out
        out = @put(out, @get(xs, i))
        i = @add(i, 1)
    }
}

slice_or(xs [u8], from usize, end usize, fallback [u8]) -> [u8], bool {
    if @gt(from, end) return fallback, false
    if @gt(end, @len(xs)) return fallback, false

    out [u8] = .{}
    i usize = from
    loop {
        if @ge(i, end) return out, true
        out = @put(out, @get(xs, i))
        i = @add(i, 1)
    }
}

take(xs [u8], count usize) -> [u8] | BytesError {
    if @gt(count, @len(xs)) return BytesOutOfBounds

    out [u8] = .{}
    i usize = 0
    loop {
        if @ge(i, count) return out
        out = @put(out, @get(xs, i))
        i = @add(i, 1)
    }
}

take_or(xs [u8], count usize, fallback [u8]) -> [u8], bool {
    if @gt(count, @len(xs)) return fallback, false

    out [u8] = .{}
    i usize = 0
    loop {
        if @ge(i, count) return out, true
        out = @put(out, @get(xs, i))
        i = @add(i, 1)
    }
}

drop(xs [u8], count usize) -> [u8] | BytesError {
    if @gt(count, @len(xs)) return BytesOutOfBounds

    out [u8] = .{}
    i usize = count
    loop {
        if @ge(i, @len(xs)) return out
        out = @put(out, @get(xs, i))
        i = @add(i, 1)
    }
}

drop_or(xs [u8], count usize, fallback [u8]) -> [u8], bool {
    if @gt(count, @len(xs)) return fallback, false

    out [u8] = .{}
    i usize = count
    loop {
        if @ge(i, @len(xs)) return out, true
        out = @put(out, @get(xs, i))
        i = @add(i, 1)
    }
}

first(xs [u8]) -> u8 {
    return @get(xs, 0)
}

first_or(xs [u8], fallback u8) -> u8, bool {
    if @eq(@len(xs), 0) return fallback, false
    return first(xs), true
}

last(xs [u8]) -> u8 {
    return @get(xs, @sub(@len(xs), 1))
}

last_or(xs [u8], fallback u8) -> u8, bool {
    if @eq(@len(xs), 0) return fallback, false
    return last(xs), true
}

.matches_at(xs [u8], needle [u8], pos usize) -> bool {
    if @gt(@add(pos, @len(needle)), @len(xs)) return false

    i usize = 0
    loop {
        if @ge(i, @len(needle)) return true
        if @ne(@get(xs, @add(pos, i)), @get(needle, i)) return false
        i = @add(i, 1)
    }
}

starts_with(xs [u8], prefix [u8]) -> bool {
    return matches_at(xs, prefix, 0)
}

ends_with(xs [u8], suffix [u8]) -> bool {
    if @gt(@len(suffix), @len(xs)) return false
    return matches_at(xs, suffix, @sub(@len(xs), @len(suffix)))
}

index_of(xs [u8], needle [u8]) -> usize | nil {
    if @eq(@len(needle), 0) return 0
    if @gt(@len(needle), @len(xs)) return nil

    last usize = @sub(@len(xs), @len(needle))
    i usize = 0
    loop {
        if matches_at(xs, needle, i) return i
        if @ge(i, last) return nil
        i = @add(i, 1)
    }
}

last_index_of(xs [u8], needle [u8]) -> usize | nil {
    if @eq(@len(needle), 0) return @len(xs)
    if @gt(@len(needle), @len(xs)) return nil

    i usize = @sub(@len(xs), @len(needle))
    loop {
        if matches_at(xs, needle, i) return i
        if @eq(i, 0) return nil
        i = @sub(i, 1)
    }
}

contains(xs [u8], needle [u8]) -> bool {
    return @ne(index_of(xs, needle), nil)
}

trim_left_byte(xs [u8], value u8) -> [u8] {
    empty [u8] = .{}
    from usize = 0
    loop {
        if @ge(from, @len(xs)) return empty
        if @ne(@get(xs, from), value) return slice_from(xs, from, @len(xs))
        from = @add(from, 1)
    }
}

trim_right_byte(xs [u8], value u8) -> [u8] {
    empty [u8] = .{}
    end usize = @len(xs)
    loop {
        if @eq(end, 0) return empty
        prev usize = @sub(end, 1)
        if @ne(@get(xs, prev), value) return slice_from(xs, 0, end)
        end = prev
    }
}

trim_byte(xs [u8], value u8) -> [u8] {
    return trim_right_byte(trim_left_byte(xs, value), value)
}

replace(xs [u8], needle [u8], replacement [u8]) -> [u8] {
    if @eq(@len(needle), 0) return copy(xs)

    out [u8] = .{}
    i usize = 0
    loop {
        if @ge(i, @len(xs)) return out
        if matches_at(xs, needle, i) {
            out = append(out, replacement)
            i = @add(i, @len(needle))
        } else {
            out = @put(out, @get(xs, i))
            i = @add(i, 1)
        }
    }
}

.slice_from(xs [u8], from usize, end usize) -> [u8] {
    out [u8] = .{}
    i usize = from
    loop {
        if @ge(i, end) return out
        out = @put(out, @get(xs, i))
        i = @add(i, 1)
    }
}
