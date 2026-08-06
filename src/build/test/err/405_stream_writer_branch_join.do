produce(stop bool, writer StreamWriter<i32>) -> nil {
    if stop {
        close(writer)
    }
}

test "a conditional finalizer must cover every path" {}
