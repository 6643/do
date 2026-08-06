produce(stop bool, writer StreamWriter<i32>) -> nil {
    if stop {
        close(writer)
    }
}

test "conditional close cannot finalize every path" {}
