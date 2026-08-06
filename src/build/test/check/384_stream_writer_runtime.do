produce(writer StreamWriter<i32>) -> nil {
    first StreamWriter<i32> = writer
    close(first)
}

test "writer runtime lease has one terminal owner" {}

start() {}
