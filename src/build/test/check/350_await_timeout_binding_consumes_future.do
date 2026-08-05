async ready() -> i32 {
    return 1
}

async wait_once() -> i32 {
    timeout i32 = 10
    pending Future<i32> = ready()
    return await(pending, timeout)
}

test "timeout await accepts a timeout binding" {}
