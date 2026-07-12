// Managed-struct direct Tuple storage slot: Cell is ARC handle leaf (not field-flattened).
Cell {
    n u8 = 0
    label text = ""
}

start() {
    items [Tuple<Cell, u8>] = .{}
    c Cell = Cell{n = 1, label = "hi"}
    pair Tuple<Cell, u8> = Tuple<Cell, u8>{c, 7}
    items = @put(items, pair)
    got Tuple<Cell, u8> = @get(items, 0)
    a Cell = @get(got, 0)
    b u8 = @get(got, 1)
    _ = a
    _ = b
}
