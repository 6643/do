Counter {
    count usize
}

test "set lambda update field" {
    state Counter = Counter{count = 2}
    state = set(state, .count, (count usize) => add(count, 3))
    if eq(get(state, .count), 5) return
}
