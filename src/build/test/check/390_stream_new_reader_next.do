async produce() -> nil {
    reader StreamReader<u8>, writer StreamWriter<u8> = new_stream<u8>(1)
    pending Future<Result<u8, nil>> = @next(reader)
    replied Result<u8, nil> = await(pending)
    _ = replied
    defer close(writer)
}

start() {}
