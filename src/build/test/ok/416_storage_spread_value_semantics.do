test "storage spread put preserves source lists" {
    xs [i32] = .{1, 2}
    rest [i32] = .{3, 4}
    joined [i32] = @put(xs, ...rest)
    empty [i32] = .{}
    empty_left [i32] = @put(empty, ...rest)
    empty_right [i32] = @put(xs, ...empty)
    same [i32] = @put(xs, ...xs)

    ok bool = true
    ok = @and(ok, @eq(@len(xs), 2))
    ok = @and(ok, @eq(@get(xs, 0), 1))
    ok = @and(ok, @eq(@get(xs, 1), 2))
    ok = @and(ok, @eq(@len(rest), 2))
    ok = @and(ok, @eq(@get(rest, 0), 3))
    ok = @and(ok, @eq(@get(rest, 1), 4))
    ok = @and(ok, @eq(@len(joined), 4))
    ok = @and(ok, @eq(@get(joined, 0), 1))
    ok = @and(ok, @eq(@get(joined, 1), 2))
    ok = @and(ok, @eq(@get(joined, 2), 3))
    ok = @and(ok, @eq(@get(joined, 3), 4))
    ok = @and(ok, @eq(@len(empty), 0))
    ok = @and(ok, @eq(@len(empty_left), 2))
    ok = @and(ok, @eq(@get(empty_left, 1), 4))
    ok = @and(ok, @eq(@len(empty_right), 2))
    ok = @and(ok, @eq(@get(empty_right, 1), 2))
    ok = @and(ok, @eq(@len(same), 4))
    ok = @and(ok, @eq(@get(same, 2), 1))
    ok = @and(ok, @eq(@get(same, 3), 2))
    if ok return
    return
}
