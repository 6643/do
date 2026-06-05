
len_text(text [u8]) -> usize {
    return len(text)
}

test "line string call arg" {
    n = len_text(
        \\hello
    )
    return
}
