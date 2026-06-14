Box {
    value [u8]
}

move_box(box Box) -> Box {
    return box
}

pass(box Box) -> Box {
    return move_box(box)
}

test "compiled managed struct return call last use move" {
    bytes [u8] = .{1, 2, 3}
    box Box = Box{value = bytes}
    out Box = pass(box)
    if @eq(@get(out, .value), .{1, 2, 3}) return
}
