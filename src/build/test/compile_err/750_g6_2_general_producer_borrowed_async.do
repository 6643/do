make_ticket = @host_func("do:g6-2-owned-record-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
consume = @host_async_func("do:g6-2-owned-record-producer@0.1.0", "consume-via-stream", (StreamWriter<borrow<Ticket>>) -> Result<nil, ProducerError>)
Ticket = @wasi_resource("do:g6-2-owned-record-producer/source/ticket", { .id i64 })
ResourceEntry {
    .ticket Ticket
}
ProducerError error = Io | Pipe | InvalidMode
produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
start() {}
