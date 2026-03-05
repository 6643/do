done() bool => true
wait(a i32, b i32, c i32) i32 => a
wait_one(a i32) i32 => a
wait_any(a i32) i32 => a
wait_all(a i32) i32 => a
cancel() bool => true
status() i32 => 1

test "async control name as user func" {
    ok = done()
    x = wait(1, 2, 3)
    y = wait_one(7)
    z = wait_any(8)
    w = wait_all(9)
    canceled = cancel()
    st = status()
    if ok return
    if canceled return
    if x return
    if y return
    if z return
    if w return
    if st return
}
