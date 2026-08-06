ready() -> i32 {
    return 1
}

race() -> nil {
    left Future<i32> = @async(ready())
    right Future<i32> = @async(ready())
    await_any(left, right)
}

test "aggregate await any consumes each future" {}
