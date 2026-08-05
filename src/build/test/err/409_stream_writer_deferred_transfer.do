async produce(writer StreamWriter<i32>) -> nil {
    defer close(writer)
    next StreamWriter<i32> = writer
}

test "a deferred writer cannot leave its cleanup scope" {}
