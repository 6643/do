ProbeError error = Io

consume(reader Stream<u8>) -> nil {
    pending Future<Result<u8, nil>> = @next(reader)
    item Result<u8, nil> = @await(pending)
    _ = item
}

produce(writer StreamWriter<u8>) -> nil {
    defer close(writer)
    pending Future<Result<nil, ProbeError>> = writer(1)
    result Result<nil, ProbeError> = @await(pending)
    _ = result
}

start() {}
