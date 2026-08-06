consume(reader Stream<u8>) -> nil {
    moved Stream<u8> = reader
    pending Future<Result<u8, nil>> = @next(reader)
    @await(pending)
    _ = moved
}

test "next uses the current reader owner" {}
