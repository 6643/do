range_i32 = @lib("range.do", range_i32)
range_usize = @lib("range.do", range_usize)
repeat_i32 = @lib("range.do", repeat_i32)
repeat_usize = @lib("range.do", repeat_usize)

test "range helpers" {
    ok bool = true

    ok = @and(ok, @eq(range_i32(2, 5), .{2, 3, 4}))
    ok = @and(ok, @eq(range_i32(5, 5), .{}))
    ok = @and(ok, @eq(range_usize(1, 4), .{1, 2, 3}))
    ok = @and(ok, @eq(range_usize(4, 4), .{}))

    ok = @and(ok, @eq(repeat_i32(7, 3), .{7, 7, 7}))
    ok = @and(ok, @eq(repeat_i32(7, 0), .{}))
    ok = @and(ok, @eq(repeat_usize(9, 2), .{9, 9}))
    ok = @and(ok, @eq(repeat_usize(9, 0), .{}))

    if ok return
}
