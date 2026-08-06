probe_read = @host_func("do:record-resource-list-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>>)
Ticket = @wasi_resource("do:record-resource-list-stream-probe/source/ticket", { .id i64 })

ResourceEntry {
    .ticket Ticket
}

ProbeError error = Io

run() -> Result<nil, ProbeError> {
    handles Tuple<Stream<[ResourceEntry]>, Future<Result<nil, ProbeError>>> = probe_read()
    reader Stream<[ResourceEntry]> = @get(handles, 0)
    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
    pending Future<Result<[ResourceEntry], nil>> = @next(reader)
    item Result<[ResourceEntry], nil> = @await(pending)
    _ = item
    completed Result<nil, ProbeError> = @await(completion)
    if @is(completed, Err) return completed
    return Ok()
}

start() {}
