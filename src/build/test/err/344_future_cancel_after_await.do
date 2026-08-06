ready() -> i32 {
    return 1
}

consume() -> nil {
    pending Future<i32> = @async(ready())
    value i32 = @await(pending)
    @cancel(pending)
}

test "cancel cannot consume an awaited future" {}
