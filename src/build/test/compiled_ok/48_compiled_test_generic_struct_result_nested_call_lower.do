#K
#V
Pair {
    .keys [K]
    .vals [V]
}

#K
#V
pair_from_parts(ks [K], vs [V]) -> Pair<K, V> {
    return Pair<K, V>{keys = ks, vals = vs}
}

#K
#V
empty_pair(key K, value V) -> Pair<K, V> {
    _ = key
    _ = value
    ks [K] = .{}
    vs [V] = .{}
    return pair_from_parts(ks, vs)
}

test "compiled generic struct result nested call lower" {
    key [u8] = ""
    value i32 = 0
    pair Pair<[u8], i32> = empty_pair(key, value)
    _ = pair
    return
}
