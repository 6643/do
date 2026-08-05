async produce(writer StreamWriter<i32>) -> nil {
    close(writer)
}

test "close finalizes writer lease" {}
