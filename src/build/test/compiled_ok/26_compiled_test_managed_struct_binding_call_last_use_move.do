Box {
    value [u8]
}

move_box(box Box) -> Box {
    return box
}

test "compiled managed struct binding call last use move" {
    bytes [u8] = .{1, 2, 3}
    box Box = Box{value = bytes}
    out Box = move_box(box)
    value [u8] = @get(out, .value)
    if @eq(value, .{1, 2, 3}) return
}
