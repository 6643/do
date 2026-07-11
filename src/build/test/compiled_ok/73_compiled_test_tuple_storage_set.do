test "compiled tuple storage set" {
    pair0 Tuple<bool, u8> = Tuple<bool, u8>{false, 1}
    xs [Tuple<bool, u8>] = .{}
    xs = @put(xs, pair0)
    next Tuple<bool, u8> = Tuple<bool, u8>{true, 9}
    xs = @set(xs, 0, next)
    got Tuple<bool, u8> = @get(xs, 0)
    if @and(@eq(@get(got, 0), true), @eq(@get(got, 1), 9)) return
}
