produce(writer StreamWriter<i32>) -> nil {
    close(writer)
    abort(writer, 1)
}

test "writer lease can finalize once" {}
