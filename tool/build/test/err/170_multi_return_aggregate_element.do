pair() -> i32, i32 {
    return 1, 2
}

test "multi return aggregate element" {
    xs [i32] = .{pair()}
    return
}
