HashMap = @lib("hash_map.do", HashMap)
empty_hash_map = @lib("hash_map.do", empty_hash_map)
hash_map_del = @lib("hash_map.do", del)
hash_len = @lib("hash_map.do", hash_len)
hash_put = @lib("hash_map.do", hash_put)

test "hash map del import" {
    key [u8] = ""
    value i32 = 0
    m HashMap<[u8], i32> = empty_hash_map(key, value)
    m = hash_put(m, "a", 1)
    m = hash_map_del(m, "a")
    if @eq(hash_len(m), 0) return
}
