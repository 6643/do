List = @lib("list.do", List)
empty_list = @lib("list.do", empty_list)
list_add = @lib("list.do", list_add)
list_items = @lib("list.do", items)

test "list storage items" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    xs = list_add(xs, 1)
    items [i32] = list_items(xs)
    if @eq(@len(items), 1) return
}

test "empty storage literal" {
    items [i32] = .{}
    if @eq(@len(items), 0) return
}

test "storage primitive put set get" {
    items [i32] = .{}
    items = @put(items, 1)
    items = @put(items, 2)
    items = @set(items, 1, 9)

    ok bool = true
    ok = @and(ok, @eq(@len(items), 2))
    ok = @and(ok, @eq(@get(items, 1), 9))
    if ok return
}
