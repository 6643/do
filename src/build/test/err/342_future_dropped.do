async ready() -> i32 {
    return 1
}

async leak() -> nil {
    pending Future<i32> = ready()
}

test "future must be consumed" {}
