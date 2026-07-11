make_outer() -> Tuple<Tuple<bool, u8>, i32> {
    outer Tuple<Tuple<bool, u8>, i32> = Tuple<Tuple<bool, u8>, i32>{Tuple<bool, u8>{true, 7}, 9}
    return outer
}

pick_flag(outer Tuple<Tuple<bool, u8>, i32>) -> bool {
    inner Tuple<bool, u8> = @get(outer, 0)
    return @get(inner, 0)
}

pick_tail(outer Tuple<Tuple<bool, u8>, i32>) -> i32 {
    return @get(outer, 1)
}

test "compiled nested tuple return param" {
    outer Tuple<Tuple<bool, u8>, i32> = make_outer()
    flag bool = pick_flag(outer)
    tail i32 = pick_tail(outer)
    if @and(@eq(flag, true), @eq(tail, 9)) return
}
