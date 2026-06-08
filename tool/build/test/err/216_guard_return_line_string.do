line_value(ok bool) -> text {
    if ok return
        \\hello
    return "fallback"
}

test "guard return line text" {
    return
}
