work(a i32) i32 => a
wait_one(x i32, y i32, z i32) i32 => x

test "async control user func mismatch falls back to builtin arity" {
    f = do work(1)
    _x = wait_one(f)
}
