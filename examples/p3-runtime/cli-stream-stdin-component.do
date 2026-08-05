stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
StdinError error = Io | IllegalByteSequence | Pipe

async run() -> nil {
    handles Tuple<Stream<u8>, Future<Result<nil, StdinError>>> = stdin_read()
    reader Stream<u8> = @get(handles, 0)
    completion Future<Result<nil, StdinError>> = @get(handles, 1)
    pending Future<Result<u8, nil>> = @next(reader)
    item Result<u8, nil> = await(pending)
    _ = item
    second_pending Future<Result<u8, nil>> = @next(reader)
    second_item Result<u8, nil> = await(second_pending)
    _ = second_item
    eof_pending Future<Result<u8, nil>> = @next(reader)
    eof Result<u8, nil> = await(eof_pending)
    _ = eof
    @cancel(completion)
}

start() {}
