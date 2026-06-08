test "compiled inferred numeric literal call" {
    x = @add(1, 2)
    if @eq(x, 3) return
}
