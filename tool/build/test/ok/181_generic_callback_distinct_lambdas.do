#A
#B
#P = (A) -> B
apply_value(value A, p P) -> B {
    return p(value)
}

test "generic callback distinct same shape lambdas" {
    first i32 = apply_value(1, (x i32) -> i32 => @add(x, 1))
    second i32 = apply_value(1, (x i32) -> i32 => @mul(x, 3))

    ok bool = true
    ok = @and(ok, @eq(first, 2))
    ok = @and(ok, @eq(second, 3))
    if ok return
}
