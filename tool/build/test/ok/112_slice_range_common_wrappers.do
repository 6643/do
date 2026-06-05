repeat_i32 = @range.do/repeat_i32
slice_first = @slice.do/first
slice_first_or = @slice.do/first_or
slice_last = @slice.do/last
slice_last_or = @slice.do/last_or
slice_drop_or = @slice.do/drop_or
slice_take_or = @slice.do/take_or

test "slice range common wrappers" {
    nums [i32] = .{1, 2, 3}
    empty [i32] = .{}
    fallback [i32] = .{9}
    missing i32 = 9
    head, head_ok = slice_take_or(nums, 2, fallback)
    bad_head, bad_head_ok = slice_take_or(nums, 4, fallback)
    tail, tail_ok = slice_drop_or(nums, 1, fallback)
    bad_tail, bad_tail_ok = slice_drop_or(nums, 4, fallback)
    first_value, first_ok = slice_first_or(nums, missing)
    missing_first, missing_first_ok = slice_first_or(empty, missing)
    last_value, last_ok = slice_last_or(nums, missing)
    missing_last, missing_last_ok = slice_last_or(empty, missing)
    repeated [i32] = repeat_i32(7, 3)

    ok bool = true
    ok = and(ok, head_ok)
    ok = and(ok, eq(head, .{1, 2}))
    ok = and(ok, not(bad_head_ok))
    ok = and(ok, eq(bad_head, fallback))
    ok = and(ok, tail_ok)
    ok = and(ok, eq(tail, .{2, 3}))
    ok = and(ok, not(bad_tail_ok))
    ok = and(ok, eq(bad_tail, fallback))
    ok = and(ok, eq(slice_first(nums), 1))
    ok = and(ok, first_ok)
    ok = and(ok, eq(first_value, 1))
    ok = and(ok, not(missing_first_ok))
    ok = and(ok, eq(missing_first, missing))
    ok = and(ok, eq(slice_last(nums), 3))
    ok = and(ok, last_ok)
    ok = and(ok, eq(last_value, 3))
    ok = and(ok, not(missing_last_ok))
    ok = and(ok, eq(missing_last, missing))
    ok = and(ok, eq(repeated, .{7, 7, 7}))
    if ok return
}
