test "compiled tuple managed leaf storage" {
    xs [Tuple<text, u8>] = .{}
    pair Tuple<text, u8> = Tuple<text, u8>{"hi", 7}
    xs = @put(xs, pair)
    got Tuple<text, u8> = @get(xs, 0)
    if @and(@eq(@get(got, 0), "hi"), @eq(@get(got, 1), 7)) return
}
