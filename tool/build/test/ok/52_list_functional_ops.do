List = @/list.do/List
list_len = @/list.do/len
list_get = @/list.do/get
list_put = @/list.do/put
list_map = @/list.do/map
list_filter = @/list.do/filter
list_fold = @/list.do/fold
list_reduce = @/list.do/reduce
list_find = @/list.do/find
list_find_index = @/list.do/find_index
list_any = @/list.do/any
list_all = @/list.do/all
list_count = @/list.do/count

test "list functional ops" {
    xs List<i32> = List<i32>{}
    xs = list_put(xs, 1)
    xs = list_put(xs, 2)
    xs = list_put(xs, 3)

    ys List<i64> = list_map(xs, (x i32) -> i64 => to_i64(add(x, 1)))
    even List<i32> = list_filter(xs, (x i32) -> bool => eq(rem(x, 2), 0))
    sum i32 = list_fold(xs, 0, (acc i32, x i32) -> i32 => add(acc, x))
    reduced i32 | nil = list_reduce(xs, (a i32, b i32) -> i32 => add(a, b))
    found i32 | nil = list_find(xs, (x i32) -> bool => eq(x, 2))
    found_i usize | nil = list_find_index(xs, (x i32) -> bool => eq(x, 2))
    has_even bool = list_any(xs, (x i32) -> bool => eq(rem(x, 2), 0))
    all_pos bool = list_all(xs, (x i32) -> bool => gt(x, 0))
    even_count usize = list_count(xs, (x i32) -> bool => eq(rem(x, 2), 0))

    ok bool = true
    ok = and(ok, eq(list_len(ys), 3))
    ok = and(ok, eq(list_get(ys, 2), 4))
    ok = and(ok, eq(list_len(even), 1))
    ok = and(ok, eq(list_get(even, 0), 2))
    ok = and(ok, eq(sum, 6))
    ok = and(ok, eq(reduced, 6))
    ok = and(ok, eq(found, 2))
    ok = and(ok, eq(found_i, 1))
    ok = and(ok, has_even)
    ok = and(ok, all_pos)
    ok = and(ok, eq(even_count, 1))
    if ok return
}

test "list functional env ops" {
    xs List<i32> = List<i32>{}
    xs = list_put(xs, 1)
    xs = list_put(xs, 2)
    xs = list_put(xs, 3)

    step i32 = 1
    ys List<i32> = list_map(xs, step, (x i32, step i32) -> i32 => add(x, step))
    over List<i32> = list_filter(xs, step, (x i32, step i32) -> bool => gt(x, step))
    found i32 | nil = list_find(xs, step, (x i32, step i32) -> bool => eq(x, add(step, 1)))
    found_i usize | nil = list_find_index(xs, step, (x i32, step i32) -> bool => eq(x, add(step, 1)))
    has_gt bool = list_any(xs, step, (x i32, step i32) -> bool => gt(x, step))
    all_gt bool = list_all(xs, step, (x i32, step i32) -> bool => gt(x, step))
    gt_count usize = list_count(xs, step, (x i32, step i32) -> bool => gt(x, step))

    ok bool = true
    ok = and(ok, eq(list_len(ys), 3))
    ok = and(ok, eq(list_get(ys, 2), 4))
    ok = and(ok, eq(list_len(over), 2))
    ok = and(ok, eq(found, 2))
    ok = and(ok, eq(found_i, 1))
    ok = and(ok, has_gt)
    ok = and(ok, not(all_gt))
    ok = and(ok, eq(gt_count, 2))
    if ok return
}

test "list update env op" {
    xs List<i32> = List<i32>{}
    xs = list_put(xs, 1)
    xs = list_put(xs, 2)

    step i32 = 10
    next List<i32> | ListError = list_update(xs, 1, step, (x i32, step i32) -> i32 => add(x, step))
    ok bool = eq(list_get(next, 1), 12)
    if ok return
}
