List = @/list.do/List

test "upper loop bind" {
    xs List<i32> = List<i32>{}
    loop Value, i = xs {
        return
    }
}
