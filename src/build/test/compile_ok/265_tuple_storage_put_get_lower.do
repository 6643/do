start() {
    xs [Tuple<bool, u8>] = .{}
    pair Tuple<bool, u8> = Tuple<bool, u8>{true, 7}
    xs = @put(xs, pair)
    got Tuple<bool, u8> = @get(xs, 0)
    if @eq(@get(got, 1), 7) { return }
    return
}
