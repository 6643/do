make_ticket = @host_func("do:g6-2-owned-record-two-list-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
consume = @host_async_func("do:g6-2-owned-record-two-list-producer@0.1.0", "consume-via-stream", (StreamWriter<TwoListEntry>) -> Result<nil, ProducerError>)
Ticket = @wasi_resource("do:g6-2-owned-record-two-list-producer/source/ticket", { .id i64 })
TwoListEntry {
    .first [u32]
    .ticket Ticket
}
ProducerError error = Io | Pipe | InvalidMode
produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
start() {}
