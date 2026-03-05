work(a i32) i32 => a

test "invalid wait arity" {
    f1 = do work(1)
    f2 = do work(2)
    _x = wait(1000, f1, f2)
}
