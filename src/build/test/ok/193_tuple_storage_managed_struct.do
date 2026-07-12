Cell {
    n u8 = 0
    label text = ""
}

test "tuple storage managed struct nested slot" {
    items [Tuple<Cell, u8>] = .{}
    c Cell = Cell{n = 1, label = "hi"}
    pair Tuple<Cell, u8> = Tuple<Cell, u8>{c, 7}
    items = @put(items, pair)
    got Tuple<Cell, u8> = @get(items, 0)
    a Cell = @get(got, 0)
    b u8 = @get(got, 1)
    ok bool = true
    ok = @and(ok, @eq(@get(a, .n), 1))
    ok = @and(ok, @eq(b, 7))
    // Nested path: storage index then Tuple slot (Cell handle); never flatten Cell fields into Tuple.
    a2 Cell = @get(items, 0, 0)
    b2 u8 = @get(items, 0, 1)
    ok = @and(ok, @eq(@get(a2, .n), 1))
    ok = @and(ok, @eq(b2, 7))
    if ok return
}
