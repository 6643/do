consume(reader Stream<u8>) -> nil {
    pending Future<Result<u8, nil>> = @next(reader)
    _ = pending
}

test "next requires an async reader body" {}
