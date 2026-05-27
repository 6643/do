List = @/list.do/List
list_empty = @/list.do/empty
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
    xs List<i32> = list_empty()
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
    return
}
