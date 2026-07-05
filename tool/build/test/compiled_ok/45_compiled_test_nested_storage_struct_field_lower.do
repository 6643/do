Box {
    .items [[u8]]
}

test "compiled nested storage struct field lower" {
    a [u8] = "a"
    xs [[u8]] = .{a}
    box Box = Box{items = xs}
    out [[u8]] = @get(box, .items)
    if @eq(@get(out, 0), "a") return
}
