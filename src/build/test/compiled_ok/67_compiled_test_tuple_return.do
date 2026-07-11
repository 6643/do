make_pair() -> Tuple<bool, u8> {
    pair Tuple<bool, u8> = Tuple<bool, u8>{true, 7}
    return pair
}

test "compiled tuple return" {
    pair Tuple<bool, u8> = make_pair()
    first bool = @get(pair, 0)
    second u8 = @get(pair, 1)
    if @and(@eq(first, true), @eq(second, 7)) return
}
