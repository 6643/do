List = @/list.do/List
list_get = @/list.do/get
list_put = @/list.do/put
list_update = @/list.do/update

test "list update existing index" {
    xs List<i32> = List<i32>{}
    xs = list_put(xs, 1)
    xs = list_put(xs, 2)

    xs = list_update(xs, 1, (x i32) -> i32 => add(x, 40))
    if eq(list_get(xs, 1), 42) return
}

