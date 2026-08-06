produce(stop bool, writer StreamWriter<i32>) -> nil {
    if stop return
    close(writer)
}

test "early return cannot bypass writer finalization" {}
