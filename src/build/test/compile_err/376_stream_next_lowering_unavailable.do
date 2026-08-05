async consume(reader Stream<u8>) -> nil {
    pending Future<Result<u8, nil>> = @next(reader)
    item Result<u8, nil> = await(pending)
    _ = item
}

start() {}
