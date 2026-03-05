status(a i32, b i32, c i32) i32 => 1
work(a i32) i32 => a

test "status user func mismatch falls back to builtin arity" {
    f = do work(1)
    _x = status(f, 1)
}
