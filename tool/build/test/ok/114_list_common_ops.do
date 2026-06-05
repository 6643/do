List = @list.do/List
empty_list = @list.do/empty_list
clear_list = @list.do/clear
list_items = @list.do/items
list_add = @list.do/list_add
list_first = @list.do/list_first
list_first_or = @list.do/list_first_or
list_has = @list.do/list_has
list_index_of = @list.do/list_index_of
list_is_empty = @list.do/list_is_empty
list_last = @list.do/list_last
list_last_or = @list.do/list_last_or

test "list common queries" {
    seed i32 = 0
    empty List<i32> = empty_list(seed)
    xs List<i32> = list_add(empty, 4, 5, 4)
    missing = list_index_of(xs, 9)
    cleared List<i32> = clear_list(xs)
    first_value, first_ok = list_first_or(xs, 9)
    missing_first, missing_first_ok = list_first_or(empty, 9)
    last_value, last_ok = list_last_or(xs, 9)
    missing_last, missing_last_ok = list_last_or(empty, 9)

    ok bool = true
    ok = and(ok, list_is_empty(empty))
    ok = and(ok, not(list_is_empty(xs)))
    ok = and(ok, list_is_empty(cleared))
    ok = and(ok, eq(list_items(xs), .{4, 5, 4}))
    ok = and(ok, eq(list_items(cleared), .{}))
    ok = and(ok, list_has(xs, 5))
    ok = and(ok, not(list_has(xs, 9)))
    ok = and(ok, eq(list_index_of(xs, 4), 0))
    ok = and(ok, eq(list_index_of(xs, 5), 1))
    ok = and(ok, eq(missing, nil))
    ok = and(ok, eq(list_first(xs), 4))
    ok = and(ok, first_ok)
    ok = and(ok, eq(first_value, 4))
    ok = and(ok, not(missing_first_ok))
    ok = and(ok, eq(missing_first, 9))
    ok = and(ok, eq(list_last(xs), 4))
    ok = and(ok, last_ok)
    ok = and(ok, eq(last_value, 4))
    ok = and(ok, not(missing_last_ok))
    ok = and(ok, eq(missing_last, 9))
    if ok return
}
