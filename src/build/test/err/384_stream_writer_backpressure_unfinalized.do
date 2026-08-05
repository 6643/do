async produce(writer StreamWriter<i32>) -> nil {
    value i32 = 1
    _ = value
}

test "writer backpressure requires a finalized lease" {}
