cancel(a i32, b i32, c i32) bool => true
work(a i32) i32 => a

test "cancel user func mismatch falls back to builtin arity" {
    f = do work(1)
    _x = cancel(f, 1)
}
