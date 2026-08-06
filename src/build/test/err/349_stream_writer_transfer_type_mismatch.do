produce(writer StreamWriter<i32>) -> nil {
    next StreamWriter<u8> = writer
    close(next)
}

test "writer transfer keeps element type" {}
