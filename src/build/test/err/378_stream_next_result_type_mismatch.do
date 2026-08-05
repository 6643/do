async consume(reader Stream<u8>) -> nil {
    pending Future<Result<i32, nil>> = @next(reader)
    await(pending)
}

test "next result item type matches reader" {}
