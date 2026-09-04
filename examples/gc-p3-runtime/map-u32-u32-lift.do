HashMap = @lib("hash_map.do", HashMap)
read = @host_func("demo:marshal-map-u32-u32/api@1.0.0", "read", () -> HashMap<u32, u32>)

start() {}
