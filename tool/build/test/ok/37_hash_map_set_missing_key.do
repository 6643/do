HashMap = @hash_map.do/HashMap
empty_hash_map = @hash_map.do/empty_hash_map
hash_len = @hash_map.do/hash_len
hash_set_or = @hash_map.do/hash_set_or

test "hash map set missing key" {
    key [u8] = ""
    value i32 = 0
    m HashMap<[u8], i32> = empty_hash_map(key, value)
    next, ok = hash_set_or(m, "a", 1)
    if and(not(ok), eq(hash_len(next), 0)) return
}
