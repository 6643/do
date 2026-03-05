work(a i32) i32 => a

test "future wait many controls" {
    f1 = do work(1)
    f2 = do work(2)
    f3 = do work(3)

    _out = wait(f1)
    _out_t = wait(1000, f1)
    one = wait_one(1000, f1, f2, f3)
    any = wait_any(1000, f1, f2)
    all = wait_all(1000, f1, f2, f3)

    _s = status(f1)
    if done(f1) return
    if one return
    if any return
    if all return
}
