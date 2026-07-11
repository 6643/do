#T
#Q = (T) -> T
update_value(x T, f Q) -> T {
    value T = f(x)
    return value
}

test "generic callback typed local" {
    i i32 = 2
    result i32 = update_value(i, (x i32) -> i32 => @add(x, 40))
    if @eq(result, 42) return
}
