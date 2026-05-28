List = @/list.do/List
list_len = @/list.do/len
list_put = @/list.do/put
list_get = @/list.do/get
list_set = @/list.do/set
list_at = @/list.do/at

test "list lib ops" {
    xs List<i32> = List<i32>{}
    xs = list_put(xs, 1)
    xs = list_put(xs, 2)
    xs = list_set(xs, 1, 9)
    return
}

test "list lib len" {
    xs List<i32> = List<i32>{}
    xs = list_put(xs, 1)
    xs = list_put(xs, 2)
    if eq(list_len(xs), 2) return
}

test "list lib get" {
    xs List<i32> = List<i32>{}
    xs = list_put(xs, 1)
    xs = list_put(xs, 2)
    xs = list_set(xs, 1, 9)
    expected i32 = 9
    if eq(list_get(xs, 1), expected) return
}

test "list lib at" {
    xs List<i32> = List<i32>{}
    xs = list_put(xs, 1)
    xs = list_put(xs, 2)
    if eq(list_at(xs, 0), 1) return
}
