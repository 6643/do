async ready() -> i32 {
    return 1
}

async consume() -> nil {
    pending Future<i32> = ready()
    value i32 = await(pending)
    @cancel(pending)
}

test "cancel cannot consume an awaited future" {}
