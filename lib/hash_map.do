List = @/list.do/List
list_empty = @/list.do/empty
list_len = @/list.do/len
list_put = @/list.do/put
list_get = @/list.do/get
list_set = @/list.do/set
list_items = @/list.do/items
Text = @/text.do/Text

MapError = MissingKey

#K
#V
Map {
    .len usize = 0
    .keys [K] = storage()
    .vals [V] = storage()
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
empty() -> Map<K, V> {
    return Map<K, V>{}
}

#K
#V
len(m Map<K, V>) -> usize {
    return get(m, .len)
}

#K
#V
keys(m Map<K, V>) -> List<K> {
    return List<K>{
        len = len(m),
        items = get(m, .keys),
    }
}

#K
#V
values(m Map<K, V>) -> List<V> {
    return List<V>{
        len = len(m),
        items = get(m, .vals),
    }
}

#K
#V
.index_of(m Map<K, V>, key K) -> usize | nil {
    i usize = 0
    loop {
        if ge(i, len(m)) return nil
        if eq(at(get(m, .keys), i), key) return i
        i = add(i, 1)
    }
}

#K
#V
has(m Map<K, V>, key K) -> bool {
    idx = .index_of(m, key)
    return ne(idx, nil)
}

#K
#V
get(m Map<K, V>, key K) -> V | nil {
    idx = .index_of(m, key)
    if eq(idx, nil) return nil
    index usize = idx
    return at(get(m, .vals), index)
}

#K
#V
put(m Map<K, V>, key K, value V) -> Map<K, V> {
    idx = .index_of(m, key)
    if eq(idx, nil) {
        next_keys [K] = list_put(keys(m), key)
        next_vals [V] = list_put(values(m), value)
        return Map<K, V>{
            len = add(len(m), 1),
            keys = get(next_keys, .items),
            vals = get(next_vals, .items),
        }
    }

    index usize = idx
    next_vals [V] = set(get(m, .vals), index, value)
    return Map<K, V>{
        len = len(m),
        keys = get(m, .keys),
        vals = next_vals,
    }
}

#K
#V
set(m Map<K, V>, key K, value V) -> Map<K, V> | MapError {
    idx = .index_of(m, key)
    if eq(idx, nil) return MissingKey
    index usize = idx
    next_vals [V] = set(get(m, .vals), index, value)
    return Map<K, V>{
        len = len(m),
        keys = get(m, .keys),
        vals = next_vals,
    }
}

#K
#V
entries(m Map<K, V>) -> List<Entry<K, V>> {
    out List<Entry<K, V>> = list_empty()
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
