// Managed fields inside a Tuple direct struct slot remain non-packable (v1).
// Pure-scalar Point slots are compile_ok/272 + ok/192.
Cell {
    n u8 = 0
    label text = ""
}

start() {
    items [Tuple<Cell, u8>] = .{}
}
