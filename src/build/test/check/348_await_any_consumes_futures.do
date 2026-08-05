async ready() -> i32 {
    return 1
}

async race() -> nil {
    left Future<i32> = ready()
    right Future<i32> = ready()
    await_any(left, right)
}

test "aggregate await any consumes each future" {}
