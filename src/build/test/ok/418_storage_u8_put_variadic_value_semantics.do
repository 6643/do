test "u8 storage variadic put preserves source list" {
    data [u8] = "a"
    joined [u8] = @put(data, 98, 99)
    empty [u8] = .{}
    empty_joined [u8] = @put(empty, 7, 8)

    ok bool = true
    ok = @and(ok, @eq(@len(data), 1))
    ok = @and(ok, @eq(@get(data, 0), 97))
    ok = @and(ok, @eq(@len(joined), 3))
    ok = @and(ok, @eq(@get(joined, 0), 97))
    ok = @and(ok, @eq(@get(joined, 1), 98))
    ok = @and(ok, @eq(@get(joined, 2), 99))
    ok = @and(ok, @eq(@len(empty), 0))
    ok = @and(ok, @eq(@len(empty_joined), 2))
    ok = @and(ok, @eq(@get(empty_joined, 0), 7))
    ok = @and(ok, @eq(@get(empty_joined, 1), 8))
    if ok return
    return
}
