start() {
    xs [Tuple<Tuple<bool, u8>, i32>] = .{}
    inner Tuple<bool, u8> = Tuple<bool, u8>{false, 3}
    outer Tuple<Tuple<bool, u8>, i32> = Tuple<Tuple<bool, u8>, i32>{inner, 42}
    xs = @put(xs, outer)
    got Tuple<Tuple<bool, u8>, i32> = @get(xs, 0)
    leaf Tuple<bool, u8> = @get(got, 0)
    if @and(@eq(@get(leaf, 1), 3), @eq(@get(got, 1), 42)) { return }
    return
}
