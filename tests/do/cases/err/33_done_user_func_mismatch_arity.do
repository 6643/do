done(a i32, b i32, c i32) bool => true

test "done user func mismatch falls back to builtin arity" {
    f = do work(1)
    if done(f, 1) return
}

work(a i32) i32 => a
