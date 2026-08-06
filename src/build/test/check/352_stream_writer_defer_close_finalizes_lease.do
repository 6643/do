produce(writer StreamWriter<i32>) -> nil {
    defer close(writer)
}

test "defer close finalizes writer lease" {}
