produce(writer StreamWriter<i32>) -> nil {
    abort(writer, 1, 2)
}

test "abort accepts one error argument" {}
