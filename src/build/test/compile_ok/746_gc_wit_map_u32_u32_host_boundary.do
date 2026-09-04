HashMap = @lib("hash_map.do", HashMap)
write = @host_func("demo:marshal-map-u32-u32/api@1.0.0", "write", (HashMap<u32, u32>) -> nil)

start() {}
