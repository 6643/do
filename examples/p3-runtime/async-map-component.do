HashMap = @lib("hash_map.do", HashMap)
empty_hash_map = @lib("hash_map.do", empty_hash_map)
hash_put = @lib("hash_map.do", hash_put)

submit = @host_async_func("demo:map-async-probe/api@0.1.0", "submit", (HashMap<u32, u32>) -> u32)

helper(values HashMap<u32, u32>) -> u32 {
    pending Future<u32> = submit(values)
    return @await(pending)
}

run() -> u32 {
    key u32 = 0
    value u32 = 0
    values HashMap<u32, u32> = empty_hash_map(key, value)
    values = hash_put(values, 7, 70)
    values = hash_put(values, 9, 90)
    child Future<u32> = @async(helper(values))
    return @await(child)
}
