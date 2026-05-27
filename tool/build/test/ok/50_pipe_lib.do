pipe = @/pipe.do/pipe

test "pipe same type chain" {
    result i32 = pipe(
        2,
        (x i32) -> i32 => add(x, 1),
        (x i32) -> i32 => mul(x, 3),
    )
    if eq(result, 9) return
}
