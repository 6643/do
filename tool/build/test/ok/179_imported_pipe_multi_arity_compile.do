pipe = @lib("fp.do", pipe)

bool_to_i32(x bool) -> i32 {
    if x return 1
    return 0
}

test "imported pipe multiple arities compile" {
    same i32 = pipe(2, (x i32) -> i32 => @add(x, 1), (x i32) -> i32 => @mul(x, 3))
    hetero i32 = pipe(2, (x i32) -> i64 => @as(i64, @add(x, 1)), (x i64) -> bool => @gt(x, 0), bool_to_i32)

    ok bool = true
    ok = @and(ok, @eq(same, 9))
    ok = @and(ok, @eq(hetero, 1))
    if ok return
}
