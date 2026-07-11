test "compiled tuple path chain managed leaf" {
    xs [Tuple<text, u8>] = .{Tuple<text, u8>{"ab", 9}}
    t text = @get(xs, 0, 0)
    n u8 = @get(xs, 0, 1)
    if @and(@eq(t, "ab"), @eq(n, 9)) return
}
