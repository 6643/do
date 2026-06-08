Box {
    value [u8]
}

start() {
    one_text [u8] = "one"
    two_text [u8] = "two"
    one Box = Box{value = one_text}
    two Box = Box{value = two_text}
    xs [Box] = .{one}
    xs = @set(xs, 0, two)
    xs = @put(xs, one)
    out Box = @get(xs, 1)
    return
}
