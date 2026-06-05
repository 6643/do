List = @list.do/List
empty_list = @list.do/empty_list
list_add = @list.do/list_add
list_items = @list.do/items

test "list add variadic" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    xs = list_add(xs, 1, 2, 3)
    items [i32] = list_items(xs)
    if ne(len(items), 3) return
    if ne(get(items, 0), 1) return
    if ne(get(items, 1), 2) return
    if ne(get(items, 2), 3) return
    return
}
