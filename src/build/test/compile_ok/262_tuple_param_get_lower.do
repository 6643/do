pair_first(pair Tuple<bool, u8>) -> bool {
    return @get(pair, 0)
}

start() {
    pair Tuple<bool, u8> = Tuple<bool, u8>{true, 7}
    first bool = pair_first(pair)
    return
}
