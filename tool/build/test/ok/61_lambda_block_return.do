List = @list.do/List
empty_list = @list.do/empty_list
map = @list.do/map

test "lambda block return" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    result = map(xs, (x i32) -> i32 { return add(x, 1) })
    return
}
