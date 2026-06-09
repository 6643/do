Counter {
    len i32
    add i32
    to_i32 i32
}

test "core name fields allowed" {
    item Counter = Counter{len = 1, add = 2, to_i32 = 3}
    ok bool = @eq(@get(item, .len), 1)
    ok = @and(ok, @eq(@get(item, .add), 2))
    ok = @and(ok, @eq(@get(item, .to_i32), 3))
    if ok return
}
