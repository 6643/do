Counter {
    len i32
    add i32
    popcnt i32
}

test "core name fields allowed" {
    item Counter = Counter{len = 1, add = 2, popcnt = 3}
    ok bool = @eq(@get(item, .len), 1)
    ok = @and(ok, @eq(@get(item, .add), 2))
    ok = @and(ok, @eq(@get(item, .popcnt), 3))
    if ok return
}
