pair_first(pair Tuple<bool, u8>) -> bool {
    return @get(pair, 0)
}

test "compiled tuple param" {
    pair Tuple<bool, u8> = Tuple<bool, u8>{true, 7}
    first bool = pair_first(pair)
    if @eq(first, true) return
}
