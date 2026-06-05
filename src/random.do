List = @list.do/List
empty_list = @list.do/empty_list
list_add = @list.do/list_add
list_items = @list.do/items
now = @time.do/now

Random {
    .state u64 = 1
}

seed(value u64) -> Random {
    if eq(value, 0) return Random{state = 1}
    return Random{state = value}
}

from_time() -> Random {
    return seed(rem(to_u64(now()), 2147483647))
}

next_u64(r Random) -> Random, u64 {
    state u64 = rem(add(mul(get(r, .state), 48271), 1), 2147483647)
    return Random{state = state}, state
}

next_u32(r Random) -> Random, u32 {
    next_r Random = r
    next_r, value = next_u64(next_r)
    return next_r, to_u32(value)
}

next_bool(r Random) -> Random, bool {
    next_r Random = r
    next_r, value = next_u64(next_r)
    return next_r, eq(rem(value, 2), 1)
}

range(r Random, max u64) -> Random, u64 {
    if eq(max, 0) return r, 0
    next_r Random = r
    next_r, value = next_u64(next_r)
    return next_r, rem(value, max)
}

fill_bytes(r Random, count usize) -> Random, [u8] {
    seed u8 = 0
    out List<u8> = empty_list(seed)
    i usize = 0
    state Random = r
    loop {
        if eq(i, count) return state, list_items(out)
        state, value = next_u64(state)
        out = list_add(out, to_u8(rem(value, 256)))
        i = add(i, 1)
    }
}
