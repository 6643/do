ready() -> i32 {
    return 1
}

join() -> nil {
    left Future<i32> = @async(ready())
    right Future<i32> = @async(ready())
    await_all(left, right)
    @await(left)
}

test "aggregate await consumes every future" {}
