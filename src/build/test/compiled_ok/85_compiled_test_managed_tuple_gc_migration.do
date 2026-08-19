test "compiled managed tuple rebuild preserves old payload" {
    old [u8] = "abc"
    pair Tuple<text, [u8]> = Tuple<text, [u8]>{"tag", old}
    next [u8] = @set(old, 0, 65)
    updated Tuple<text, [u8]> = Tuple<text, [u8]>{@get(pair, 0), next}

    original [u8] = @get(pair, 1)
    changed [u8] = @get(updated, 1)
    ok bool = @and(@eq(original, "abc"), @eq(changed, "Abc"))
    if ok return
}
