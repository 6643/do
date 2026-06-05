Set = @set.do/Set
clear_set = @set.do/clear
empty_set = @set.do/empty_set
set_add_many = @set.do/set_add_many
set_difference = @set.do/set_difference
set_from_items = @set.do/set_from_items
set_has = @set.do/set_has
set_intersection = @set.do/set_intersection
set_is_empty = @set.do/set_is_empty
set_items = @set.do/items
set_len = @set.do/set_len
set_union = @set.do/set_union

test "set common ops" {
    seed i32 = 0
    xs Set<i32> = empty_set(seed)
    xs = set_add_many(xs, 1, 2, 2, 3)
    ys Set<i32> = set_from_items(seed, .{3, 4})
    empty Set<i32> = set_from_items(seed, .{})

    merged Set<i32> = set_union(xs, ys)
    shared Set<i32> = set_intersection(xs, ys)
    left_only Set<i32> = set_difference(xs, ys)
    cleared Set<i32> = clear_set(xs)

    ok bool = true
    ok = and(ok, set_is_empty(empty))
    ok = and(ok, not(set_is_empty(xs)))
    ok = and(ok, set_is_empty(cleared))
    ok = and(ok, eq(set_len(xs), 3))
    ok = and(ok, eq(set_len(cleared), 0))
    ok = and(ok, eq(set_items(xs), .{1, 2, 3}))
    ok = and(ok, eq(set_items(cleared), .{}))
    ok = and(ok, eq(set_len(merged), 4))
    ok = and(ok, set_has(merged, 1))
    ok = and(ok, set_has(merged, 4))
    ok = and(ok, eq(set_items(shared), .{3}))
    ok = and(ok, eq(set_items(left_only), .{1, 2}))
    if ok return
}
