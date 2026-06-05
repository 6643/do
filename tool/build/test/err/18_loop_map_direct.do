HashMap = @hash_map.do/HashMap
empty_hash_map = @hash_map.do/empty_hash_map

test "loop map direct" {
    key [u8] = ""
    value i32 = 0
    m HashMap<[u8], i32> = empty_hash_map(key, value)
    loop v, k = m {
        consume(k, v)
    }
}
