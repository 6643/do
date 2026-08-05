async produce(writer StreamWriter<i32>) -> nil {
    next StreamWriter<i32> = writer
    close(next)
}

test "writer lease transfers to new owner" {}
