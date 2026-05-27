List = @/list.do/List
list_empty = @/list.do/empty
list_put = @/list.do/put
list_items = @/list.do/items

test "list storage items" {
    xs List<i32> = list_empty()
    xs = list_put(xs, 1)
    items [i32] = list_items(xs)
    if eq(len(items), 1) return
}
