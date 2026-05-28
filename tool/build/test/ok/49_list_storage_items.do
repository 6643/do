List = @/list.do/List
list_put = @/list.do/put
list_items = @/list.do/items

test "list storage items" {
    xs List<i32> = List<i32>{}
    xs = list_put(xs, 1)
    items [i32] = list_items(xs)
    if eq(len(items), 1) return
}

test "empty storage literal" {
    items [i32] = .{}
    if eq(len(items), 0) return
}

test "storage primitive put set at" {
    items [i32] = .{}
    items = put(items, 1)
    items = put(items, 2)
    items = set(items, 1, 9)

    ok bool = true
    ok = and(ok, eq(len(items), 2))
    ok = and(ok, eq(at(items, 1), 9))
    if ok return
}
