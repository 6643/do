.double(x i32) -> i32 {
    return add(x, x)
}

test "private func call with dot" {
    y i32 = .double(2)
    return
}
