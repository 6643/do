ready() -> i32 {
    return 1
}

consume() -> i32 {
    pending Future<i32> = @async(ready())
    first i32 = @await(pending)
    return @await(pending)
}

test "future is consumed once" {}
