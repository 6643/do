.double(x i32) -> i32 => @mul(x, 2)

test "compiled private func" {
    got i32 = double(3)
    if @eq(got, 6) return
}
