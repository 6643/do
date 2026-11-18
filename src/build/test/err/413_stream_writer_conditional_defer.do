produce(stop bool, writer StreamWriter<i32>) -> nil {
    defer(stop) close(writer)
}

test "conditional defer cannot guarantee writer finalization" {}
