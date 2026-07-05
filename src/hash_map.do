#K
#V
HashMap {
    .len usize
    .keys [K]
    .vals [V]
}

#K
#V
hash_map_from_parts(ks [K], vs [V]) -> HashMap<K, V> {
    return HashMap<K, V>{len = @len(ks), keys = ks, vals = vs}
}

#K
#V
empty_hash_map(key K, value V) -> HashMap<K, V> {
    _ = key
    _ = value
    ks [K] = .{}
    vs [V] = .{}
    return hash_map_from_parts(ks, vs)
}

#K
#V
Entry {
    key K
    value V
}

hash(bytes [u8]) -> u64 {
    h u64 = 0
    loop byte, _ = bytes {
        h = @rem(@add(@mul(h, 131), @as(u64, byte)), 1000000007)
    }
    return h
}

#K
#V
hash_len(m HashMap<K, V>) -> usize {
    return @get(m, .len)
}

#K
#V
hash_is_empty(m HashMap<K, V>) -> bool {
    return @eq(hash_len(m), 0)
}

#K
#V
clear(m HashMap<K, V>) -> HashMap<K, V> {
    _ = m
    ks [K] = .{}
    vs [V] = .{}
    return hash_map_from_parts(ks, vs)
}

#K
#V
keys(m HashMap<K, V>) -> [K] {
    return @get(m, .keys)
}

#K
#V
values(m HashMap<K, V>) -> [V] {
    return @get(m, .vals)
}

#K
#V
.index_of(m HashMap<K, V>, key K) -> usize | nil {
    i usize = 0
    loop {
        if @ge(i, hash_len(m)) return nil
        if @eq(@get(@get(m, .keys), i), key) return i
        i = @add(i, 1)
    }
}

#K
#V
.require_index(m HashMap<K, V>, key K) -> usize {
    idx = index_of(m, key)
    if @eq(idx, nil) {
        _ = @get(@get(m, .keys), hash_len(m))
        return hash_len(m)
    }
    return idx
}

#K
#V
has(m HashMap<K, V>, key K) -> bool {
    idx = index_of(m, key)
    return @ne(idx, nil)
}

#K
#V
hash_has(m HashMap<K, V>, key K) -> bool {
    return has(m, key)
}

#K
#V
hash_get(m HashMap<K, V>, key K) -> V {
    index usize = require_index(m, key)
    return @get(@get(m, .vals), index)
}

#K
#V
hash_get_or(m HashMap<K, V>, key K, fallback V) -> V, bool {
    idx = index_of(m, key)
    if @eq(idx, nil) return fallback, false
    index usize = idx
    return @get(@get(m, .vals), index), true
}

#K
#V
hash_put(m HashMap<K, V>, key K, value V) -> HashMap<K, V> {
    idx = index_of(m, key)
    if @eq(idx, nil) {
        add_keys [K] = keys(m)
        add_vals [V] = values(m)
        added_keys [K] = @put(add_keys, key)
        added_vals [V] = @put(add_vals, value)
        return hash_map_from_parts(added_keys, added_vals)
    }

    index usize = idx
    set_vals [V] = values(m)
    updated_vals [V] = @set(set_vals, index, value)
    set_keys [K] = keys(m)
    return hash_map_from_parts(set_keys, updated_vals)
}

#K
#V
hash_set(m HashMap<K, V>, key K, value V) -> HashMap<K, V> {
    index usize = require_index(m, key)
    data_vals [V] = values(m)
    next_vals [V] = @set(data_vals, index, value)
    data_keys [K] = keys(m)
    return hash_map_from_parts(data_keys, next_vals)
}

#K
#V
hash_set_or(m HashMap<K, V>, key K, value V) -> HashMap<K, V>, bool {
    idx = index_of(m, key)
    if @eq(idx, nil) return m, false
    index usize = idx
    data_vals [V] = values(m)
    next_vals [V] = @set(data_vals, index, value)
    data_keys [K] = keys(m)
    next HashMap<K, V> = hash_map_from_parts(data_keys, next_vals)
    return next, true
}

#K
#V
#Q = (V) -> V
update(m HashMap<K, V>, key K, f Q) -> HashMap<K, V> {
    index usize = require_index(m, key)
    next_vals [V] = @set(@get(m, .vals), index, f(@get(@get(m, .vals), index)))
    return HashMap<K, V>{len = hash_len(m), keys = @get(m, .keys), vals = next_vals}
}

#K
#V
#Q = (V) -> V
update_or(m HashMap<K, V>, key K, f Q) -> HashMap<K, V>, bool {
    idx = index_of(m, key)
    if @eq(idx, nil) return m, false
    index usize = idx
    next_vals [V] = @set(@get(m, .vals), index, f(@get(@get(m, .vals), index)))
    next HashMap<K, V> = hash_map_from_parts(@get(m, .keys), next_vals)
    return next, true
}

#K
#V
del(m HashMap<K, V>, key K) -> HashMap<K, V> {
    index usize = require_index(m, key)
    next_keys [K] = .{}
    next_vals [V] = .{}
    loop entry_key, entry_index = @get(m, .keys) {
        if @ne(entry_index, index) {
            next_keys = @put(next_keys, entry_key)
            next_vals = @put(next_vals, @get(@get(m, .vals), entry_index))
        }
    }
    return HashMap<K, V>{len = @sub(hash_len(m), 1), keys = next_keys, vals = next_vals}
}

#K
#V
del_or(m HashMap<K, V>, key K) -> HashMap<K, V>, bool {
    idx = index_of(m, key)
    if @eq(idx, nil) return m, false
    index usize = idx
    next_keys [K] = .{}
    next_vals [V] = .{}
    loop entry_key, entry_index = @get(m, .keys) {
        if @ne(entry_index, index) {
            next_keys = @put(next_keys, entry_key)
            next_vals = @put(next_vals, @get(@get(m, .vals), entry_index))
        }
    }
    next HashMap<K, V> = hash_map_from_parts(next_keys, next_vals)
    return next, true
}

#K
#V
entries(m HashMap<K, V>) -> [Entry<K, V>] {
    out [Entry<K, V>] = .{}
    i usize = 0
    loop {
        if @eq(i, hash_len(m)) return out
        entry Entry<K, V> = Entry<K, V>{key = @get(@get(m, .keys), i), value = @get(@get(m, .vals), i)}
        out = @put(out, entry)
        i = @add(i, 1)
    }
}
