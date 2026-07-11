double(x i32) -> i32 => @mul(x, 2)

test "compiled inferred call bind" {
    got = double(3)
    if @eq(got, 6) return
}
