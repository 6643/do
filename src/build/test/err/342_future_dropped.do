ready() -> i32 {
    return 1
}

leak() -> nil {
    pending Future<i32> = @async(ready())
}

test "future must be consumed" {}
