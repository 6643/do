List = @list.do/List
empty_list = @list.do/empty_list
list_del = @list.do/del
list_len = @list.do/list_len
list_add = @list.do/list_add

test "list del import" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    xs = list_add(xs, 1)
    xs = list_del(xs, 0)
    if eq(list_len(xs), 0) return
}
