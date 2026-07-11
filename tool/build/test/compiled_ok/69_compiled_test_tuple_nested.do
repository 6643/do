test "compiled nested tuple" {
    outer Tuple<Tuple<bool, u8>, i32> = Tuple<Tuple<bool, u8>, i32>{Tuple<bool, u8>{true, 7}, 9}
    inner Tuple<bool, u8> = @get(outer, 0)
    flag bool = @get(inner, 0)
    code u8 = @get(inner, 1)
    tail i32 = @get(outer, 1)
    if @and(@and(@eq(flag, true), @eq(code, 7)), @eq(tail, 9)) return
}
