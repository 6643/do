List = @/list.do/List
list_len = @/list.do/len
list_put = @/list.do/put
list_get = @/list.do/get
list_set = @/list.do/set
list_items = @/list.do/items
Text = @/text.do/Text

MapError = MissingKey

#K
#V
HashMap {
    .len usize = 0
    .keys [K] = .{}
    .vals [V] = .{}
}

#K
#V
Entry {
    key K
    value V
}

hash(text Text) -> u64 {
    h u64 = 0
    loop b, _ = text {
        h = rem(add(mul(h, 131), to_u64(b)), 1000000007)
    }
    return h
}

#K
#V
len(m HashMap<K, V>) -> usize {
    return get(m, .len)
}

#K
#V
keys(m HashMap<K, V>) -> List<K> {
    return List<K>{
        len = len(m),
        items = get(m, .keys),
    }
}

#K
#V
values(m HashMap<K, V>) -> List<V> {
    return List<V>{
        len = len(m),
        items = get(m, .vals),
    }
}

#K
#V
.index_of(m HashMap<K, V>, key K) -> usize | nil {
    i usize = 0
    loop {
        if ge(i, len(m)) return nil
        if eq(at(get(m, .keys), i), key) return i
        i = add(i, 1)
    }
}

#K
#V
has(m HashMap<K, V>, key K) -> bool {
    idx = .index_of(m, key)
    return ne(idx, nil)
}

#K
#V
get(m HashMap<K, V>, key K) -> V | nil {
    idx = .index_of(m, key)
    if eq(idx, nil) return nil
    index usize = idx
    return at(get(m, .vals), index)
}

#K
#V
put(m HashMap<K, V>, key K, value V) -> HashMap<K, V> {
    idx = .index_of(m, key)
    if eq(idx, nil) {
        next_keys [K] = list_put(keys(m), key)
        next_vals [V] = list_put(values(m), value)
        return HashMap<K, V>{
            len = add(len(m), 1),
            keys = get(next_keys, .items),
            vals = get(next_vals, .items),
        }
    }

    index usize = idx
    next_vals [V] = set(get(m, .vals), index, value)
    return HashMap<K, V>{
        len = len(m),
        keys = get(m, .keys),
        vals = next_vals,
    }
}

#K
#V
set(m HashMap<K, V>, key K, value V) -> HashMap<K, V> | MapError {
    idx = .index_of(m, key)
    if eq(idx, nil) return MissingKey
    index usize = idx
    next_vals [V] = set(get(m, .vals), index, value)
    return HashMap<K, V>{
        len = len(m),
        keys = get(m, .keys),
        vals = next_vals,
    }
}

#K
#V
update(m HashMap<K, V>, key K, f (V) -> V) -> HashMap<K, V> | MapError {
    idx = .index_of(m, key)
    if eq(idx, nil) return MissingKey
    index usize = idx
    next_vals [V] = set(get(m, .vals), index, f(at(get(m, .vals), index)))
    return HashMap<K, V>{
        len = len(m),
        keys = get(m, .keys),
        vals = next_vals,
    }
}

#K
#V
del(m HashMap<K, V>, key K) -> HashMap<K, V> | MapError {
    idx = .index_of(m, key)
    if eq(idx, nil) return MissingKey
    index usize = idx
    next_keys [K] = .{}
    next_vals [V] = .{}
    loop k, i = get(m, .keys) {
        if ne(i, index) {
            next_keys = put(next_keys, k)
            next_vals = put(next_vals, at(get(m, .vals), i))
        }
    }
    return HashMap<K, V>{
        len = sub(len(m), 1),
        keys = next_keys,
        vals = next_vals,
    }
}

#K
#V
entries(m HashMap<K, V>) -> List<Entry<K, V>> {
    out List<Entry<K, V>> = List<Entry<K, V>>{}
    i usize = 0
    loop {
        if eq(i, len(m)) return out
        out = list_put(out, Entry<K, V>{
            key = at(get(m, .keys), i),
            value = at(get(m, .vals), i),
        })
        i = add(i, 1)
    }
}
