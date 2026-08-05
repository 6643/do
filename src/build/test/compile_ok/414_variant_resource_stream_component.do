probe_read = @host_func("do:variant-resource-stream-canonical@0.1.0", "read-via-stream", () -> Tuple<Stream<Ticket | nil | EventError>, Future<Result<nil, EventError>>>)
Ticket = @wasi_resource("do:variant-resource-stream-canonical/source/ticket", { .id i64 })
EventError error = Io

start() {
}
