Box {
    value [u8]
}

make_boxes() -> Box, Box {
    left_text [u8] = "left"
    right_text [u8] = "right"
    left Box = Box{value = left_text}
    right Box = Box{value = right_text}
    return left, right
}

start() {
    first_text [u8] = "first"
    second_text [u8] = "second"
    first Box = Box{value = first_text}
    second Box = Box{value = second_text}
    first, second = make_boxes()
    return
}
