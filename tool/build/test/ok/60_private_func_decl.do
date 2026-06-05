.double(x i32) -> i32 => mul(x, 2)

test "private func decl" {
    got = double(3)
    expected i32 = 6
    if eq(got, expected) return
}
