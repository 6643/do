
len_text(bytes [u8]) -> usize {
    return @len(bytes)
}

test "line text call arg" {
    n = len_text(
        \\hello
    )
    return
}
