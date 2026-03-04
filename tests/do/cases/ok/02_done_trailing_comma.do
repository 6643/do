work(a i32) i32 => a

test "done trailing comma" {
    f = do work(1)
    if done(f,) return
}
