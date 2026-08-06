consume(reader Stream<u8>) -> nil {
    pending Future<Result<u8, nil>> = @next(reader)
    item Result<u8, nil> = @await(pending)
    if @is(item, Ok) {
        value u8 = item
        _ = value
    }
}

start() {}
