List = @/list.do/List
list_del = @/list.do/del

test "list del import" {
    xs List<i32> = List<i32>{}
    xs = list_del(xs, 0)
    return
}
