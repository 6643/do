make_outer() -> Tuple<Tuple<bool, u8>, i32> {
    outer Tuple<Tuple<bool, u8>, i32> = Tuple<Tuple<bool, u8>, i32>{Tuple<bool, u8>{true, 7}, 9}
    return outer
}

pick_flag(outer Tuple<Tuple<bool, u8>, i32>) -> bool {
    inner Tuple<bool, u8> = @get(outer, 0)
    return @get(inner, 0)
}

start() {
    outer Tuple<Tuple<bool, u8>, i32> = make_outer()
    flag bool = pick_flag(outer)
    return
}
