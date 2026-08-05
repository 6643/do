stdin_read = @host("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u16>, Future<Result<nil, StdinError>>>)
StdinError error = Io | IllegalByteSequence | Pipe

async read_word() -> nil {
    handles Tuple<Stream<u16>, Future<Result<nil, StdinError>>> = stdin_read()
    reader Stream<u16> = @get(handles, 0)
    completion Future<Result<nil, StdinError>> = @get(handles, 1)
    pending Future<Result<u16, nil>> = @next(reader)
    item Result<u16, nil> = await(pending)
    _ = item
    @cancel(completion)
}

start() {}
