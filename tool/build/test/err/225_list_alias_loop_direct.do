MyList = @list.do/List
empty_list = @list.do/empty_list

test "list alias loop direct" {
    seed i32 = 0
    xs MyList<i32> = empty_list(seed)
    loop x, i = xs {
        consume(x, i)
    }
}
