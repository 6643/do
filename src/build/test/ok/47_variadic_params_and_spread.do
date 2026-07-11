sum(first i32, rest ...i32) -> i32 => first

forward(prefix i32, rest ...i32) -> i32 => sum(prefix, ...rest)

test "variadic params and spread args" {
    x = forward(1, 2, 3)
    expected i32 = 1
    if @eq(x, expected) return
}
