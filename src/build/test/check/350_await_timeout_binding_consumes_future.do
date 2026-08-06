ready() -> i32 {
    return 1
}

wait_once() -> i32 {
    timeout i32 = 10
    pending Future<i32> = @async(ready())
    return await(pending, timeout)
}

test "timeout await accepts a timeout binding" {}
