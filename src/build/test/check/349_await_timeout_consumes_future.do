ready() -> i32 {
    return 1
}

wait_once() -> i32 {
    pending Future<i32> = @async(ready())
    return await(pending, 10)
}

test "timeout await consumes its future" {}
