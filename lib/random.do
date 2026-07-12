List = @lib("list.do", List)
empty_list = @lib("list.do", empty_list)
list_add = @lib("list.do", list_add)
list_items = @lib("list.do", items)
unix_ms = @lib("time.do", unix_ms)

.host_random_bytes = @wasi_func("random/random/get-random-bytes", (u64) -> [u8])
.host_random_u64 = @wasi_func("random/random/get-random-u64", () -> u64)

Random {
    .state u64 = 1
}

seed(value u64) -> Random {
    if @eq(value, 0) return Random{state = 1}
    return Random{state = value}
}

from_time() -> Random {
    return seed(@rem(@as(u64, unix_ms()), 2147483647))
}

random_u64() -> u64 {
    return host_random_u64()
}

random_bytes(count usize) -> [u8] {
    return host_random_bytes(@as(u64, count))
}

next_u64(r Random) -> Random, u64 {
    state u64 = @rem(@add(@mul(@get(r, .state), 48271), 1), 2147483647)
    return Random{state = state}, state
}

next_u32(r Random) -> Random, u32 {
    next_r Random = r
    next_r, value = next_u64(next_r)
    return next_r, @as(u32, value)
}

next_bool(r Random) -> Random, bool {
    next_r Random = r
    next_r, value = next_u64(next_r)
    return next_r, @eq(@rem(value, 2), 1)
}

range(r Random, limit u64) -> Random, u64 {
    if @eq(limit, 0) return r, 0
    next_r Random = r
    next_r, value = next_u64(next_r)
    return next_r, @rem(value, limit)
}

fill_bytes(r Random, count usize) -> Random, [u8] {
    seed u8 = 0
    out List<u8> = empty_list(seed)
    i usize = 0
    state Random = r
    loop {
        if @eq(i, count) return state, list_items(out)
        state, value = next_u64(state)
        out = list_add(out, @as(u8, @rem(value, 256)))
        i = @add(i, 1)
    }
}
