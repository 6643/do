test "invalid loop header" {
    list_a = List<i8>{1, 2}
    loop val, idx, x := list_a {
        return
    }
}
