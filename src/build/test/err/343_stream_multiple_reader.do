consume(reader StreamReader<i32>) -> nil {
    first StreamReader<i32> = reader
    second StreamReader<i32> = reader
}

test "reader is affine" {}
