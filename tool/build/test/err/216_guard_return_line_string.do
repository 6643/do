text(ok bool) -> [u8] {
    if ok return
        \\hello
    return "fallback"
}

test "guard return line string" {
    return
}
