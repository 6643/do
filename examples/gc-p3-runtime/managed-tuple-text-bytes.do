rewrite(pair Tuple<text, [u8]>) -> Tuple<text, [u8]> {
    return Tuple<text, [u8]>{@get(pair, 0), @set(@get(pair, 1), 0, 65)}
}

start() {}
