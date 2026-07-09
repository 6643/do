Box {
    data [u8]
}

step_box(n i32, box Box) -> Box {
    if @eq(n, 0) return box
    next i32 = @sub(n, 1)
    return step_box(next, box)
}

start() {
    box Box = .{data = "a"}
    out Box = step_box(2, box)
    return
}
