List = @lib("list.do", List)
empty_list = @lib("list.do", empty_list)
list_get = @lib("list.do", list_get)
list_add = @lib("list.do", list_add)
list_update = @lib("list.do", update)

test "list update existing index" {
    seed i32 = 0
    xs List<i32> = empty_list(seed)
    xs = list_add(xs, 1)
    xs = list_add(xs, 2)

    xs = list_update(xs, 1, (x i32) -> i32 => @add(x, 40))
    if @eq(list_get(xs, 1), 42) return
}
