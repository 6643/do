Box {
    value [u8]
}

start() {
    xs [i32] = .{1}
    xs = @put(xs, 2, 3)
    a i32 = @get(xs, 1)
    b i32 = @get(xs, 2)

    data [u8] = "a"
    data = @put(data, 98, 99)
    c u8 = @get(data, 2)

    one_text [u8] = "one"
    two_text [u8] = "two"
    three_text [u8] = "three"
    one Box = Box{value = one_text}
    two Box = Box{value = two_text}
    three Box = Box{value = three_text}
    boxes [Box] = .{one}
    boxes = @put(boxes, two, three)
    out Box = @get(boxes, 2)
    return
}
