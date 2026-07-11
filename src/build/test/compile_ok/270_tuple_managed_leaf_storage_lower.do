start() {
    xs [Tuple<text, u8>] = .{}
    pair Tuple<text, u8> = Tuple<text, u8>{"hi", 7}
    xs = @put(xs, pair)
    got Tuple<text, u8> = @get(xs, 0)
    leaf text = @get(got, 0)
    flag u8 = @get(got, 1)
    _ = leaf
    _ = flag
}
