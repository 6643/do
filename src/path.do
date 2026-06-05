_slash u8 = 47
_dot u8 = 46

is_absolute(path [u8]) -> bool {
    if eq(len(path), 0) return false
    return eq(get(path, 0), _slash)
}

is_empty(path [u8]) -> bool {
    return eq(len(path), 0)
}

.slice_bytes(xs [u8], from usize, end usize) -> [u8] {
    out [u8] = .{}
    i usize = from
    loop {
        if ge(i, end) return out
        out = put(out, get(xs, i))
        i = add(i, 1)
    }
}

.last_slash(path [u8]) -> usize | nil {
    if eq(len(path), 0) return nil
    i usize = sub(len(path), 1)
    loop {
        if eq(get(path, i), _slash) return i
        if eq(i, 0) return nil
        i = sub(i, 1)
    }
}

.append_path(out [u8], part [u8]) -> [u8] {
    if eq(len(part), 0) return out
    next [u8] = out
    if eq(len(next), 0) return slice_bytes(part, 0, len(part))
    if ne(get(next, sub(len(next), 1)), _slash) {
        next = put(next, _slash)
    }
    loop byte, _ = part {
        next = put(next, byte)
    }
    return next
}

join(a [u8], b [u8], rest ...[u8]) -> [u8] {
    out [u8] = append_path(a, b)
    loop part, _ = rest {
        out = append_path(out, part)
    }
    return out
}

basename(path [u8]) -> [u8] {
    idx = last_slash(path)
    if eq(idx, nil) return slice_bytes(path, 0, len(path))
    from usize = add(idx, 1)
    return slice_bytes(path, from, len(path))
}

dirname(path [u8]) -> [u8] {
    idx = last_slash(path)
    if eq(idx, nil) return "."
    end usize = idx
    if eq(end, 0) return "/"
    return slice_bytes(path, 0, end)
}

extname(path [u8]) -> [u8] {
    base [u8] = basename(path)
    if eq(len(base), 0) return ""
    i usize = sub(len(base), 1)
    loop {
        if eq(get(base, i), _dot) return slice_bytes(base, i, len(base))
        if eq(i, 0) return ""
        i = sub(i, 1)
    }
}
