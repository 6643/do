#T
Set {
    .len usize
    .items [T]
}

#T
set_from_items(seed T, data [T]) -> Set<T> {
    out Set<T> = empty_set(seed)
    loop item, _ = data {
        out = set_add(out, item)
    }
    return out
}

#T
empty_set(seed T) -> Set<T> {
    _ = seed
    data [T] = .{}
    return Set<T>{len = 0, items = data}
}

#T
set_len(xs Set<T>) -> usize {
    return get(xs, .len)
}

#T
set_is_empty(xs Set<T>) -> bool {
    return eq(set_len(xs), 0)
}

#T
items(xs Set<T>) -> [T] {
    return get(xs, .items)
}

#T
set_has(xs Set<T>, value T) -> bool {
    loop item, _ = items(xs) {
        if eq(item, value) return true
    }
    return false
}

#T
set_add(xs Set<T>, value T) -> Set<T> {
    if set_has(xs, value) return xs
    data [T] = put(items(xs), value)
    return Set<T>{len = add(set_len(xs), 1), items = data}
}

#T
set_add_many(xs Set<T>, value T, rest ...T) -> Set<T> {
    out Set<T> = set_add(xs, value)
    loop item, _ = rest {
        out = set_add(out, item)
    }
    return out
}

#T
set_del(xs Set<T>, value T) -> Set<T> {
    if not(set_has(xs, value)) return xs
    data [T] = .{}
    loop item, _ = items(xs) {
        if ne(item, value) {
            data = put(data, item)
        }
    }
    return Set<T>{len = sub(set_len(xs), 1), items = data}
}

#T
set_union(a Set<T>, b Set<T>) -> Set<T> {
    out Set<T> = a
    loop item, _ = items(b) {
        out = set_add(out, item)
    }
    return out
}

#T
set_intersection(a Set<T>, b Set<T>) -> Set<T> {
    out Set<T> = clear(a)
    loop item, _ = items(a) {
        if set_has(b, item) {
            out = set_add(out, item)
        }
    }
    return out
}

#T
set_difference(a Set<T>, b Set<T>) -> Set<T> {
    out Set<T> = clear(a)
    loop item, _ = items(a) {
        if not(set_has(b, item)) {
            out = set_add(out, item)
        }
    }
    return out
}

#T
clear(xs Set<T>) -> Set<T> {
    _ = xs
    data [T] = .{}
    return Set<T>{len = 0, items = data}
}
