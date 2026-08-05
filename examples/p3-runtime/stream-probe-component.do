probe_read = @host_func("do:stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<u8>, Future<Result<nil, ProbeError>>>)
ProbeError error = Io | IllegalByteSequence | Pipe

async run() -> nil {
    handles Tuple<Stream<u8>, Future<Result<nil, ProbeError>>> = probe_read()
    reader Stream<u8> = @get(handles, 0)
    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
    first_pending Future<Result<u8, nil>> = @next(reader)
    first_item Result<u8, nil> = await(first_pending)
    _ = first_item
    second_pending Future<Result<u8, nil>> = @next(reader)
    second_item Result<u8, nil> = await(second_pending)
    _ = second_item
    eof_pending Future<Result<u8, nil>> = @next(reader)
    eof_item Result<u8, nil> = await(eof_pending)
    _ = eof_item
    @cancel(completion)
}

start() {}
