HashMap = @hash_map.do/HashMap
empty_hash_map = @hash_map.do/empty_hash_map
hash_len = @hash_map.do/hash_len
hash_get = @hash_map.do/hash_get
hash_put = @hash_map.do/hash_put
has = @hash_map.do/has

test "hash map lib ops" {
    key [u8] = ""
    value i32 = 0
    m HashMap<[u8], i32> = empty_hash_map(key, value)
    m = hash_put(m, "a", 1)
    m = hash_put(m, "b", 2)
    return
}

test "hash map len" {
    key [u8] = ""
    value i32 = 0
    m HashMap<[u8], i32> = empty_hash_map(key, value)
    m = hash_put(m, "a", 1)
    m = hash_put(m, "b", 2)
    if eq(hash_len(m), 2) return
}

test "hash map get" {
    key [u8] = ""
    value i32 = 0
    m HashMap<[u8], i32> = empty_hash_map(key, value)
    m = hash_put(m, "a", 1)
    expected i32 = 1
    if eq(hash_get(m, "a"), expected) return
}

test "hash map has" {
    key [u8] = ""
    value i32 = 0
    m HashMap<[u8], i32> = empty_hash_map(key, value)
    m = hash_put(m, "b", 2)
    if has(m, "b") return
}
