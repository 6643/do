HashMap = @lib("hash_map.do", HashMap)
Entry = @lib("hash_map.do", Entry)
empty_hash_map = @lib("hash_map.do", empty_hash_map)
hash_entries = @lib("hash_map.do", entries)
hash_has = @lib("hash_map.do", hash_has)
hash_is_empty = @lib("hash_map.do", hash_is_empty)
hash_keys = @lib("hash_map.do", keys)
hash_put = @lib("hash_map.do", hash_put)
hash_values = @lib("hash_map.do", values)
clear_hash_map = @lib("hash_map.do", clear)

test "hash map common wrappers" {
    key [u8] = ""
    value i32 = 0
    empty HashMap<[u8], i32> = empty_hash_map(key, value)
    m HashMap<[u8], i32> = hash_put(empty, "score", 9)

    ok bool = true
    ok = @and(ok, hash_is_empty(empty))
    ok = @and(ok, @not(hash_is_empty(m)))
    ok = @and(ok, hash_has(m, "score"))
    ok = @and(ok, @not(hash_has(m, "missing")))
    entries [Entry<[u8], i32>] = hash_entries(m)
    ok = @and(ok, @eq(hash_keys(m), .{"score"}))
    ok = @and(ok, @eq(hash_values(m), .{9}))
    ok = @and(ok, @eq(@len(entries), 1))
    ok = @and(ok, @eq(@get(@get(entries, 0), .key), "score"))
    ok = @and(ok, @eq(@get(@get(entries, 0), .value), 9))
    cleared HashMap<[u8], i32> = clear_hash_map(m)
    ok = @and(ok, hash_is_empty(cleared))
    ok = @and(ok, @not(hash_has(cleared, "score")))
    if ok return
}
