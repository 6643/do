work(a i32) i32 => a

test "invalid wait many timeout arity" {
    f1 = do work(1)
    _x = wait_one(f1)
}
