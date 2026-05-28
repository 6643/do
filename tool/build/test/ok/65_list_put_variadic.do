List = @/list.do/List
list_put = @/list.do/put
list_items = @/list.do/items

test "list put variadic" {
    xs List<i32> = List<i32>{}
    xs = list_put(xs, 1, 2, 3)
    items [i32] = list_items(xs)
    if ne(len(items), 3) return
    if ne(at(items, 0), 1) return
    if ne(at(items, 1), 2) return
    if ne(at(items, 2), 3) return
    return
}
