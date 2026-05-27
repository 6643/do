List = @/list.do/List
empty = @/list.do/empty
get = @/list.do/get

test "list negative index" {
    xs List<i32> = empty()
    last = get(xs, -1)
    return
}
