slice_first = @lib("slice.do", first)
slice_first_or = @lib("slice.do", first_or)
slice_last = @lib("slice.do", last)
slice_last_or = @lib("slice.do", last_or)

test "slice access helpers" {
    nums [i32] = .{1, 2, 3}
    empty [i32] = .{}
    missing i32 = 9

    first_value, first_ok = slice_first_or(nums, missing)
    missing_first, missing_first_ok = slice_first_or(empty, missing)
    last_value, last_ok = slice_last_or(nums, missing)
    missing_last, missing_last_ok = slice_last_or(empty, missing)

    ok bool = true
    ok = @and(ok, @eq(slice_first(nums), 1))
    ok = @and(ok, first_ok)
    ok = @and(ok, @eq(first_value, 1))
    ok = @and(ok, @not(missing_first_ok))
    ok = @and(ok, @eq(missing_first, missing))
    ok = @and(ok, @eq(slice_last(nums), 3))
    ok = @and(ok, last_ok)
    ok = @and(ok, @eq(last_value, 3))
    ok = @and(ok, @not(missing_last_ok))
    ok = @and(ok, @eq(missing_last, missing))
    if ok return
}
