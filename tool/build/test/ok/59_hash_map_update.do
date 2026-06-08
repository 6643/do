HashMap = @lib("hash_map.do", HashMap)
empty_hash_map = @lib("hash_map.do", empty_hash_map)
hash_get = @lib("hash_map.do", hash_get)
hash_put = @lib("hash_map.do", hash_put)
hash_update = @lib("hash_map.do", update)
hash_update_or = @lib("hash_map.do", update_or)
hash_len = @lib("hash_map.do", hash_len)

test "hash map update existing key" {
    key [u8] = ""
    value i32 = 0
    m HashMap<[u8], i32> = empty_hash_map(key, value)
    m = hash_put(m, "score", 2)
    m = hash_update(m, "score", (x i32) -> i32 => @add(x, 40))

    if @eq(hash_get(m, "score"), 42) return
}

test "hash map update missing key" {
    key [u8] = ""
    value i32 = 0
    m HashMap<[u8], i32> = empty_hash_map(key, value)
    next, ok = hash_update_or(m, "score", (x i32) -> i32 => @add(x, 1))

    if @and(@not(ok), @eq(hash_len(next), 0)) return
}
