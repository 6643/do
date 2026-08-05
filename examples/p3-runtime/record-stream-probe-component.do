probe_read = @host_func("do:record-stream-probe@0.1.0", "read-via-stream", () -> Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>>)

ProbeEntry {
    .id u32
    .label text
}

ProbeError error = Io | NoEntry

async run() -> Result<nil, ProbeError> {
    handles Tuple<Stream<ProbeEntry>, Future<Result<nil, ProbeError>>> = probe_read()
    reader Stream<ProbeEntry> = @get(handles, 0)
    completion Future<Result<nil, ProbeError>> = @get(handles, 1)
    loop {
        pending Future<Result<ProbeEntry, nil>> = @next(reader)
        item Result<ProbeEntry, nil> = await(pending)
        if @is(item, Ok) {
            entry ProbeEntry = item
            _ = entry
        } else {
            break
        }
    }
    completed Result<nil, ProbeError> = await(completion)
    if @is(completed, Err) return completed
    return Ok()
}

start() {}
