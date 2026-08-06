produce(stop bool, writer StreamWriter<i32>) -> nil {
    if stop {
        close(writer)
    } else {
        close(writer)
    }
}

test "both branches finalize the writer" {}
