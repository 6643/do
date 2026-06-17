test "core as isize convert" {
    i i8 = 1
    y isize = @as(isize, i)
    if @eq(y, 1) return
}
