ready() -> i32 {
    return 1
}

join() -> nil {
    left Future<i32> = @async(ready())
    right Future<i32> = @async(ready())
    await_all(left, right)
}

test "aggregate await consumes each future" {}
