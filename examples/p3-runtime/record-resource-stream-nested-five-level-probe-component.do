probe_read = @host_func("do:record-resource-stream-nested-five-level@0.1.0", "read-via-stream", () -> Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>>)
Ticket = @wasi_resource("do:record-resource-stream-nested-five-level/source/ticket", { .id i64 })

UltraEntry {
    .ticket Ticket
}

DeepestEntry {
    .ultra UltraEntry
}

DeeperEntry {
    .deepest DeepestEntry
}

DeepEntry {
    .deeper DeeperEntry
}

InnerEntry {
    .deep DeepEntry
}

ResourceEntry {
    .inner InnerEntry
}

ProbeError error = Io | NoEntry

run() -> Result<nil, ProbeError> {
    handles Tuple<Stream<ResourceEntry>, Future<Result<nil, ProbeError>>> = probe_read()
    reader Stream<ResourceEntry> = @get(handles, 0)
    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
    loop {
        pending Future<Result<ResourceEntry, nil>> = @next(reader)
        item Result<ResourceEntry, nil> = @await(pending)
        if @is(item, Ok) {
            entry ResourceEntry = item
            _ = entry
        } else {
            break
        }
    }
    completed Result<nil, ProbeError> = @await(completion)
    if @is(completed, Err) return completed
    return Ok()
}

start() {}
