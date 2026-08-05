probe_read = @host_func("do:variant-resource-stream-unknown@0.1.0", "read-via-stream", () -> Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>>)
Ticket = @wasi_resource("do:variant-resource-stream-unknown/source/ticket", { .id i64 })
EventError error = Io

async run() -> Result<nil, EventError> {
    handles Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>> = probe_read()
    reader Stream<Ticket | nil | EventError> = @get(handles, 0)
    completion Future<Result<nil, EventError>> = @get(handles, 1)
    pending Future<Result<Ticket | nil | EventError, nil>> = @next(reader)
    event Result<Ticket | nil | EventError, nil> = await(pending)
    _ = event
    return await(completion)
}
