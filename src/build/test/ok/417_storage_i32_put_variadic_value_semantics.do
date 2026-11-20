test "i32 storage variadic put preserves source list" {
    xs [i32] = .{1}
    joined [i32] = @put(xs, 2, 3, 4)
    empty [i32] = .{}
    empty_joined [i32] = @put(empty, 7, 8)

    ok bool = true
    ok = @and(ok, @eq(@len(xs), 1))
    ok = @and(ok, @eq(@get(xs, 0), 1))
    ok = @and(ok, @eq(@len(joined), 4))
    ok = @and(ok, @eq(@get(joined, 0), 1))
    ok = @and(ok, @eq(@get(joined, 1), 2))
    ok = @and(ok, @eq(@get(joined, 2), 3))
    ok = @and(ok, @eq(@get(joined, 3), 4))
    ok = @and(ok, @eq(@len(empty), 0))
    ok = @and(ok, @eq(@len(empty_joined), 2))
    ok = @and(ok, @eq(@get(empty_joined, 0), 7))
    ok = @and(ok, @eq(@get(empty_joined, 1), 8))
    if ok return
    return
}
