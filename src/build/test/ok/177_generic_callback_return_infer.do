#A
#B
#P = (A) -> B
apply_value(value A, p P) -> B {
    return p(value)
}

test "generic callback return infer" {
    result i32 = apply_value(2, (x i32) -> i32 => @add(x, 1))
    if @eq(result, 3) return
}
