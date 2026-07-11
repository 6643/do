SliceError error = SliceOutOfBounds | SliceInvalidRange

#T
slice(xs [T], from usize, end usize) -> [T] | SliceError {
    if @gt(from, end) return SliceInvalidRange
    if @gt(end, @len(xs)) return SliceOutOfBounds

    out [T] = .{}
    i usize = from
    loop {
        if @ge(i, end) return out
        out = @put(out, @get(xs, i))
        i = @add(i, 1)
    }
}

#T
slice_or(xs [T], from usize, end usize, fallback [T]) -> [T], bool {
    if @gt(from, end) return fallback, false
    if @gt(end, @len(xs)) return fallback, false

    out [T] = .{}
    i usize = from
    loop {
        if @ge(i, end) return out, true
        out = @put(out, @get(xs, i))
        i = @add(i, 1)
    }
}

#T
first(xs [T]) -> T {
    return @get(xs, 0)
}

#T
first_or(xs [T], fallback T) -> T, bool {
    if @eq(@len(xs), 0) return fallback, false
    return first(xs), true
}

#T
last(xs [T]) -> T {
    return @get(xs, @sub(@len(xs), 1))
}

#T
last_or(xs [T], fallback T) -> T, bool {
    if @eq(@len(xs), 0) return fallback, false
    return last(xs), true
}

#T
take(xs [T], count usize) -> [T] | SliceError {
    if @gt(count, @len(xs)) return SliceOutOfBounds
    return slice(xs, 0, count)
}

#T
take_or(xs [T], count usize, fallback [T]) -> [T], bool {
    if @gt(count, @len(xs)) return fallback, false

    out [T] = .{}
    i usize = 0
    loop {
        if @ge(i, count) return out, true
        out = @put(out, @get(xs, i))
        i = @add(i, 1)
    }
}

#T
drop(xs [T], count usize) -> [T] | SliceError {
    if @gt(count, @len(xs)) return SliceOutOfBounds
    return slice(xs, count, @len(xs))
}

#T
drop_or(xs [T], count usize, fallback [T]) -> [T], bool {
    if @gt(count, @len(xs)) return fallback, false

    out [T] = .{}
    i usize = count
    loop {
        if @ge(i, @len(xs)) return out, true
        out = @put(out, @get(xs, i))
        i = @add(i, 1)
    }
}
