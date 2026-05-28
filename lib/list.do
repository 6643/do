ListError = OutOfBounds

#T
List {
    .len usize = 0
    .items [T] = .{}
}

#T
len(xs List<T>) -> usize {
    return get(xs, .len)
}

#T
items(xs List<T>) -> [T] {
    return get(xs, .items)
}

#T
at(xs List<T>, i usize) -> T {
    return at(get(xs, .items), i)
}

#T
get(xs List<T>, i usize) -> T | nil {
    if ge(i, len(xs)) return nil
    return at(xs, i)
}

#T
put(xs List<T>, value T, rest ...T) -> List<T> {
    data [T] = get(xs, .items)
    next_data [T] = put(data, value)
    next_len usize = add(len(xs), 1)
    loop x, _ = rest {
        next_data = put(next_data, x)
        next_len = add(next_len, 1)
    }
    return List<T>{
        len = next_len,
        items = next_data,
    }
}

#T
set(xs List<T>, i usize, value T) -> List<T> | ListError {
    if ge(i, len(xs)) return OutOfBounds
    data [T] = get(xs, .items)
    next_data [T] = set(data, i, value)
    return List<T>{
        len = len(xs),
        items = next_data,
    }
}

#T
update(xs List<T>, i usize, f (T) -> T) -> List<T> | ListError {
    if ge(i, len(xs)) return OutOfBounds
    return set(xs, i, f(at(xs, i)))
}

#T
#P
update(xs List<T>, i usize, env P, f (T, P) -> T) -> List<T> | ListError {
    if ge(i, len(xs)) return OutOfBounds
    return set(xs, i, f(at(xs, i), env))
}

#T
del(xs List<T>, i usize) -> List<T> | ListError {
    if ge(i, len(xs)) return OutOfBounds
    next_items [T] = .{}
    loop x, idx = xs {
        if ne(idx, i) {
            next_items = put(next_items, x)
        }
    }
    return List<T>{
        len = sub(len(xs), 1),
        items = next_items,
    }
}

#T
clear(_ List<T>) -> List<T> {
    return List<T>{}
}

#T
#U
map(xs List<T>, f (T) -> U) -> List<U> {
    out List<U> = List<U>{}
    loop x, _ = xs {
        out = put(out, f(x))
    }
    return out
}

#T
#P
#U
map(xs List<T>, env P, f (T, P) -> U) -> List<U> {
    out List<U> = List<U>{}
    loop x, _ = xs {
        out = put(out, f(x, env))
    }
    return out
}

#T
filter(xs List<T>, f (T) -> bool) -> List<T> {
    out List<T> = List<T>{}
    loop x, _ = xs {
        if f(x) {
            out = put(out, x)
        }
    }
    return out
}

#T
#P
filter(xs List<T>, env P, f (T, P) -> bool) -> List<T> {
    out List<T> = List<T>{}
    loop x, _ = xs {
        if f(x, env) {
            out = put(out, x)
        }
    }
    return out
}

#T
#U
fold(xs List<T>, init U, f (U, T) -> U) -> U {
    out U = init
    loop x, _ = xs {
        out = f(out, x)
    }
    return out
}

#T
reduce(xs List<T>, f (T, T) -> T) -> T | nil {
    if eq(len(xs), 0) return nil

    out T = at(xs, 0)
    i usize = 1
    loop {
        if ge(i, len(xs)) return out
        out = f(out, at(xs, i))
        i = add(i, 1)
    }
}

#T
find(xs List<T>, f (T) -> bool) -> T | nil {
    loop x, _ = xs {
        if f(x) return x
    }
    return nil
}

#T
#P
find(xs List<T>, env P, f (T, P) -> bool) -> T | nil {
    loop x, _ = xs {
        if f(x, env) return x
    }
    return nil
}

#T
find_index(xs List<T>, f (T) -> bool) -> usize | nil {
    loop x, i = xs {
        if f(x) return i
    }
    return nil
}

#T
#P
find_index(xs List<T>, env P, f (T, P) -> bool) -> usize | nil {
    loop x, i = xs {
        if f(x, env) return i
    }
    return nil
}

#T
any(xs List<T>, f (T) -> bool) -> bool {
    loop x, _ = xs {
        if f(x) return true
    }
    return false
}

#T
#P
any(xs List<T>, env P, f (T, P) -> bool) -> bool {
    loop x, _ = xs {
        if f(x, env) return true
    }
    return false
}

#T
all(xs List<T>, f (T) -> bool) -> bool {
    loop x, _ = xs {
        if not(f(x)) return false
    }
    return true
}

#T
#P
all(xs List<T>, env P, f (T, P) -> bool) -> bool {
    loop x, _ = xs {
        if not(f(x, env)) return false
    }
    return true
}

#T
count(xs List<T>, f (T) -> bool) -> usize {
    out usize = 0
    loop x, _ = xs {
        if f(x) {
            out = add(out, 1)
        }
    }
    return out
}

#T
#P
count(xs List<T>, env P, f (T, P) -> bool) -> usize {
    out usize = 0
    loop x, _ = xs {
        if f(x, env) {
            out = add(out, 1)
        }
    }
    return out
}
