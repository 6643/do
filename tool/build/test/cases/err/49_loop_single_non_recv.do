List = @/list.do/List
empty = @/list.do/empty

test "loop single non recv" {
    xs List<i32> = empty()
    loop v = xs {
        return
    }
}
