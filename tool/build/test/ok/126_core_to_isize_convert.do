test "core to_isize convert" {
    i i8 = 1
    y isize = @to_isize(i)
    if @eq(y, 1) return
}
