async ready() -> i32 {
    return 1
}

async join() -> nil {
    left Future<i32> = ready()
    right Future<i32> = ready()
    await_all(left, right)
}

test "aggregate await consumes each future" {}
