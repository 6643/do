#A
#B
#P = (A) -> B
apply_value(value A, p P) -> B {
    return p(value)
}

bool_to_i32(x bool) -> i32 {
    if x return 1
    return 0
}

test "generic callback function ref infer" {
    result i32 = apply_value(true, bool_to_i32)
    if @eq(result, 1) return
}
