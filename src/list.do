fp_map = @lib("fp.do", map)
fp_filter = @lib("fp.do", filter)
fp_fold = @lib("fp.do", fold)
fp_reduce = @lib("fp.do", reduce)
fp_find = @lib("fp.do", find)
fp_find_index = @lib("fp.do", find_index)
fp_any = @lib("fp.do", any)
fp_all = @lib("fp.do", all)
fp_count = @lib("fp.do", count)

#T
List {
    .len usize
    .items [T]
}

#T
list_from_items(data [T]) -> List<T> {
    return List<T>{len = @len(data), items = data}
}

#T
empty_list(seed T) -> List<T> {
    _ = seed
    data [T] = .{}
    return list_from_items(data)
}

#T
list_len(xs List<T>) -> usize {
    return @get(xs, .len)
}

#T
list_is_empty(xs List<T>) -> bool {
    return @eq(list_len(xs), 0)
}

#T
items(xs List<T>) -> [T] {
    return @get(xs, .items)
}

#T
list_index_of(xs List<T>, value T) -> usize | nil {
    loop item, index = items(xs) {
        if @eq(item, value) return index
    }
    return nil
}

#T
list_has(xs List<T>, value T) -> bool {
    return @ne(list_index_of(xs, value), nil)
}

#T
list_get(xs List<T>, i usize) -> T {
    return @get(@get(xs, .items), i)
}

#T
list_get_or(xs List<T>, i usize, fallback T) -> T, bool {
    if @ge(i, list_len(xs)) return fallback, false
    return list_get(xs, i), true
}

#T
list_first(xs List<T>) -> T {
    return list_get(xs, 0)
}

#T
list_first_or(xs List<T>, fallback T) -> T, bool {
    return list_get_or(xs, 0, fallback)
}

#T
list_last(xs List<T>) -> T {
    return list_get(xs, @sub(list_len(xs), 1))
}

#T
list_last_or(xs List<T>, fallback T) -> T, bool {
    if @eq(list_len(xs), 0) return fallback, false
    return list_last(xs), true
}

#T
list_add(xs List<T>, value T, rest ...T) -> List<T> {
    data [T] = @get(xs, .items)
    next_data [T] = @put(data, value)
    loop item, _ = rest {
        next_data = @put(next_data, item)
    }
    next List<T> = @set(xs, .items, next_data)
    next = @set(next, .len, @add(list_len(xs), @add(1, @len(rest))))
    return next
}

#T
list_set(xs List<T>, i usize, value T) -> List<T> {
    data [T] = @get(xs, .items)
    next_data [T] = @set(data, i, value)
    return List<T>{len = list_len(xs), items = next_data}
}

#T
list_set_or(xs List<T>, i usize, value T) -> List<T>, bool {
    if @ge(i, list_len(xs)) return xs, false
    return list_set(xs, i, value), true
}

#T
#Q = (T) -> T
update(xs List<T>, i usize, f Q) -> List<T> {
    value T = f(list_get(xs, i))
    return list_set(xs, i, value)
}

#T
#P
#Q = (T, P) -> T
update(xs List<T>, i usize, env P, f Q) -> List<T> {
    value T = f(list_get(xs, i), env)
    return list_set(xs, i, value)
}

#T
#Q = (T) -> T
update_or(xs List<T>, i usize, f Q) -> List<T>, bool {
    if @ge(i, list_len(xs)) return xs, false
    return update(xs, i, f), true
}

#T
#P
#Q = (T, P) -> T
update_or(xs List<T>, i usize, env P, f Q) -> List<T>, bool {
    if @ge(i, list_len(xs)) return xs, false
    return update(xs, i, env, f), true
}

#T
del(xs List<T>, i usize) -> List<T> {
    _ = list_get(xs, i)
    next_items [T] = .{}
    loop item, index = items(xs) {
        if @ne(index, i) {
            next_items = @put(next_items, item)
        }
    }
    return List<T>{len = @sub(list_len(xs), 1), items = next_items}
}

#T
del_or(xs List<T>, i usize) -> List<T>, bool {
    if @ge(i, list_len(xs)) return xs, false
    return del(xs, i), true
}

#T
clear(xs List<T>) -> List<T> {
    _ = xs
    data [T] = .{}
    return list_from_items(data)
}

#T
#U
#Q = (T) -> U
map(xs List<T>, f Q) -> List<U> {
    out [U] = fp_map(items(xs), f)
    return List<U>{len = @len(out), items = out}
}

#T
#P
#U
#Q = (T, P) -> U
map(xs List<T>, env P, f Q) -> List<U> {
    out [U] = fp_map(items(xs), env, f)
    return List<U>{len = @len(out), items = out}
}

#T
#Q = (T) -> bool
filter(xs List<T>, f Q) -> List<T> {
    out [T] = fp_filter(items(xs), f)
    return List<T>{len = @len(out), items = out}
}

#T
#P
#Q = (T, P) -> bool
filter(xs List<T>, env P, f Q) -> List<T> {
    out [T] = fp_filter(items(xs), env, f)
    return List<T>{len = @len(out), items = out}
}

#T
#U
#Q = (U, T) -> U
fold(xs List<T>, init U, f Q) -> U {
    return fp_fold(items(xs), init, f)
}

#T
#Q = (T, T) -> T
reduce(xs List<T>, fallback T, f Q) -> T, bool {
    return fp_reduce(items(xs), fallback, f)
}

#T
#Q = (T) -> bool
find(xs List<T>, fallback T, f Q) -> T, bool {
    return fp_find(items(xs), fallback, f)
}

#T
#P
#Q = (T, P) -> bool
find(xs List<T>, fallback T, env P, f Q) -> T, bool {
    return fp_find(items(xs), fallback, env, f)
}

#T
#Q = (T) -> bool
find_index(xs List<T>, f Q) -> usize | nil {
    return fp_find_index(items(xs), f)
}

#T
#P
#Q = (T, P) -> bool
find_index(xs List<T>, env P, f Q) -> usize | nil {
    return fp_find_index(items(xs), env, f)
}

#T
#Q = (T) -> bool
any(xs List<T>, f Q) -> bool {
    return fp_any(items(xs), f)
}

#T
#P
#Q = (T, P) -> bool
any(xs List<T>, env P, f Q) -> bool {
    return fp_any(items(xs), env, f)
}

#T
#Q = (T) -> bool
all(xs List<T>, f Q) -> bool {
    return fp_all(items(xs), f)
}

#T
#P
#Q = (T, P) -> bool
all(xs List<T>, env P, f Q) -> bool {
    return fp_all(items(xs), env, f)
}

#T
#Q = (T) -> bool
count(xs List<T>, f Q) -> usize {
    return fp_count(items(xs), f)
}

#T
#P
#Q = (T, P) -> bool
count(xs List<T>, env P, f Q) -> usize {
    return fp_count(items(xs), env, f)
}
