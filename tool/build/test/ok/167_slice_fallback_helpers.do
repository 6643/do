slice_slice_or = @lib("slice.do", slice_or)
slice_take_or = @lib("slice.do", take_or)
slice_drop_or = @lib("slice.do", drop_or)

test "slice fallback helpers" {
    nums [i32] = .{1, 2, 3}
    fallback [i32] = .{9}

    mid, mid_ok = slice_slice_or(nums, 1, 3, fallback)
    bad_range, bad_range_ok = slice_slice_or(nums, 3, 1, fallback)
    bad_oob, bad_oob_ok = slice_slice_or(nums, 1, 4, fallback)
    head, head_ok = slice_take_or(nums, 2, fallback)
    bad_head, bad_head_ok = slice_take_or(nums, 4, fallback)
    tail, tail_ok = slice_drop_or(nums, 1, fallback)
    bad_tail, bad_tail_ok = slice_drop_or(nums, 4, fallback)

    ok bool = true
    ok = @and(ok, mid_ok)
    ok = @and(ok, @eq(mid, .{2, 3}))
    ok = @and(ok, @not(bad_range_ok))
    ok = @and(ok, @eq(bad_range, fallback))
    ok = @and(ok, @not(bad_oob_ok))
    ok = @and(ok, @eq(bad_oob, fallback))
    ok = @and(ok, head_ok)
    ok = @and(ok, @eq(head, .{1, 2}))
    ok = @and(ok, @not(bad_head_ok))
    ok = @and(ok, @eq(bad_head, fallback))
    ok = @and(ok, tail_ok)
    ok = @and(ok, @eq(tail, .{2, 3}))
    ok = @and(ok, @not(bad_tail_ok))
    ok = @and(ok, @eq(bad_tail, fallback))
    if ok return
}
