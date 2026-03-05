wait(a i32, b i32, c i32, d i32) i32 => a
work(a i32) i32 => a

test "wait user func mismatch falls back to builtin arity" {
    f = do work(1)
    _x = wait(1000, f, 1)
}
