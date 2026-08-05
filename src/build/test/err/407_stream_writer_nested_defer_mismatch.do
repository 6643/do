async produce(stop bool, writer StreamWriter<i32>) -> nil {
    if stop {
        defer close(writer)
    }
}

test "all paths must register the same writer cleanup" {}
