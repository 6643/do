stdin_read = @host_func("wasi:cli/stdin@0.3.0-rc-2025-09-16", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, StdinError>>>)
StdinError error = Io | IllegalByteSequence | Pipe

run() -> nil {
    handles Tuple<Stream<u8>, Future<Result<nil, StdinError>>> = stdin_read()
    reader Stream<u8> = @get(handles, 0)
    completion Future<Result<nil, StdinError>> = @get(handles, 1)
    pending Future<Result<u8, nil>> = @next(reader)
    item Result<u8, nil> = @await(pending)
    _ = item
    @cancel(completion)
}

start() {}
