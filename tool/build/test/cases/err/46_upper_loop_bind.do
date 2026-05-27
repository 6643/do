List = @/list.do/List
empty = @/list.do/empty

test "upper loop bind" {
    xs List<i32> = empty()
    loop Value, i = xs {
        return
    }
}
