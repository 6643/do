List = @lib("list.do", List)
empty_list = @lib("list.do", empty_list)
map = @lib("list.do", map)

test "lambda callback site" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    result = map(xs, (x i32) => @add(x, 1))
    return
}

test "lambda explicit env arg" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    step i32 = 1
    result = map(xs, step, (x i32, item_step i32) => @add(x, item_step))
    return
}
