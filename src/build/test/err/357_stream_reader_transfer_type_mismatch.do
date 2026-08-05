async consume(reader StreamReader<i32>) -> nil {
    next StreamReader<u8> = reader
}

test "reader transfer keeps element type" {}
