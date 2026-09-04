HashMap = @lib("hash_map.do", HashMap)
empty_hash_map = @lib("hash_map.do", empty_hash_map)
hash_put = @lib("hash_map.do", hash_put)
write = @host_func("demo:marshal-map-u32-u32/api@1.0.0", "write", (HashMap<u32, u32>) -> nil)

start() {
    key u32 = 0
    value u32 = 0
    values HashMap<u32, u32> = empty_hash_map(key, value)
    values = hash_put(values, 7, 70)
    values = hash_put(values, 9, 90)
    write(values)
}
