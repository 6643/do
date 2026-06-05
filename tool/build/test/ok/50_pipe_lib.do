apply = @fp.do/apply
tap = @fp.do/tap
repeat = @fp.do/repeat
fp_map = @fp.do/map
fp_filter = @fp.do/filter
fp_fold = @fp.do/fold
fp_reduce = @fp.do/reduce
fp_find = @fp.do/find
fp_find_index = @fp.do/find_index
fp_any = @fp.do/any
fp_all = @fp.do/all
fp_count = @fp.do/count
pipe = @fp.do/pipe

noop(x i32) -> nil {
    _ = x
    return
}

bool_to_i32(x bool) -> i32 {
    if x return 1
    return 0
}

test "pipe same type chain" {
    result i32 = pipe(2, (x i32) -> i32 => add(x, 1), (x i32) -> i32 => mul(x, 3))
    if eq(result, 9) return
}

test "pipe heterogenous chain" {
    result i32 = pipe(2, (x i32) -> i64 => to_i64(add(x, 1)), (x i64) -> bool => gt(x, 0), bool_to_i32)
    if eq(result, 1) return
}

test "pipe eight segments" {
    result i32 = pipe(0, (x i32) -> i32 => add(x, 1), (x i32) -> i32 => add(x, 1), (x i32) -> i32 => add(x, 1), (x i32) -> i32 => add(x, 1), (x i32) -> i32 => add(x, 1), (x i32) -> i32 => add(x, 1), (x i32) -> i32 => add(x, 1), (x i32) -> i32 => add(x, 1))
    if eq(result, 8) return
}

test "fp apply tap repeat" {
    applied i32 = apply(2, (x i32) -> i32 => mul(x, 4))
    repeated i32 = repeat(1, 3, (x i32) -> i32 => add(x, 2))
    tapped i32 = tap(repeated, noop)

    ok bool = true
    ok = and(ok, eq(applied, 8))
    ok = and(ok, eq(repeated, 7))
    ok = and(ok, eq(tapped, 7))
    if ok return
}

test "fp storage functional ops" {
    xs [i32] = .{}
    xs = put(xs, 1)
    xs = put(xs, 2)
    xs = put(xs, 3)

    ys [i64] = fp_map(xs, (x i32) -> i64 => to_i64(add(x, 1)))
    even [i32] = fp_filter(xs, (x i32) -> bool => eq(rem(x, 2), 0))
    sum i32 = fp_fold(xs, 0, (acc i32, x i32) -> i32 => add(acc, x))
    reduced, reduced_ok = fp_reduce(xs, 0, (a i32, b i32) -> i32 => add(a, b))
    found, found_ok = fp_find(xs, 0, (x i32) -> bool => eq(x, 2))
    found_i usize | nil = fp_find_index(xs, (x i32) -> bool => eq(x, 2))
    has_even bool = fp_any(xs, (x i32) -> bool => eq(rem(x, 2), 0))
    all_pos bool = fp_all(xs, (x i32) -> bool => gt(x, 0))
    even_count usize = fp_count(xs, (x i32) -> bool => eq(rem(x, 2), 0))

    ok bool = true
    ok = and(ok, eq(len(ys), 3))
    ok = and(ok, eq(get(ys, 2), 4))
    ok = and(ok, eq(len(even), 1))
    ok = and(ok, eq(get(even, 0), 2))
    ok = and(ok, eq(sum, 6))
    ok = and(ok, reduced_ok)
    ok = and(ok, eq(reduced, 6))
    ok = and(ok, found_ok)
    ok = and(ok, eq(found, 2))
    ok = and(ok, eq(found_i, 1))
    ok = and(ok, has_even)
    ok = and(ok, all_pos)
    ok = and(ok, eq(even_count, 1))
    if ok return
}

test "fp storage functional env ops" {
    xs [i32] = .{}
    xs = put(xs, 1)
    xs = put(xs, 2)
    xs = put(xs, 3)

    step i32 = 1
    ys [i32] = fp_map(xs, step, (x i32, step i32) -> i32 => add(x, step))
    over [i32] = fp_filter(xs, step, (x i32, step i32) -> bool => gt(x, step))
    found, found_ok = fp_find(xs, 0, step, (x i32, step i32) -> bool => eq(x, add(step, 1)))
    found_i usize | nil = fp_find_index(xs, step, (x i32, step i32) -> bool => eq(x, add(step, 1)))
    has_gt bool = fp_any(xs, step, (x i32, step i32) -> bool => gt(x, step))
    all_gt bool = fp_all(xs, step, (x i32, step i32) -> bool => gt(x, step))
    gt_count usize = fp_count(xs, step, (x i32, step i32) -> bool => gt(x, step))

    ok bool = true
    ok = and(ok, eq(len(ys), 3))
    ok = and(ok, eq(get(ys, 2), 4))
    ok = and(ok, eq(len(over), 2))
    ok = and(ok, found_ok)
    ok = and(ok, eq(found, 2))
    ok = and(ok, eq(found_i, 1))
    ok = and(ok, has_gt)
    ok = and(ok, not(all_gt))
    ok = and(ok, eq(gt_count, 2))
    if ok return
}
