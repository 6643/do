PairBox {
    pair Tuple<bool, u8>
}

test "compiled tuple struct field" {
    box PairBox = PairBox{pair = Tuple<bool, u8>{true, 7}}
    flag bool = @get(box, .pair, 0)
    code u8 = @get(box, .pair, 1)
    if @and(@eq(flag, true), @eq(code, 7)) return
}
