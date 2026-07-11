List = @lib("list.do", List)
empty_list = @lib("list.do", empty_list)
list_len = @lib("list.do", list_len)
list_add = @lib("list.do", list_add)
list_get = @lib("list.do", list_get)
list_get_or = @lib("list.do", list_get_or)
list_set = @lib("list.do", list_set)
list_set_or = @lib("list.do", list_set_or)

test "list lib ops" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    xs = list_add(xs, 1)
    xs = list_add(xs, 2)
    xs = list_set(xs, 1, 9)
    return
}

test "list lib len" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    xs = list_add(xs, 1)
    xs = list_add(xs, 2)
    if @eq(list_len(xs), 2) return
}

test "list lib get" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    xs = list_add(xs, 1)
    xs = list_add(xs, 2)
    xs = list_set(xs, 1, 9)
    expected i32 = 9
    if @eq(list_get(xs, 1), expected) return
}

test "list lib get_or" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    xs = list_add(xs, 1)
    xs = list_add(xs, 2)
    value, ok = list_get_or(xs, 0, 0)
    if @and(ok, @eq(value, 1)) return
}

test "list lib set_or missing" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    next, ok = list_set_or(xs, 0, 1)
    if @and(@not(ok), @eq(list_len(next), 0)) return
}
