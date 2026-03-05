test "invalid match header trailing token" {
    x = 1
    match x bad {
        _ => return,
    }
}
