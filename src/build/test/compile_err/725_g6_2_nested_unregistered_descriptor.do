make_ticket = @host_func("do:g6-2-owned-record-nested-producer/source@0.1.0", "make-ticket", (u32) -> Ticket)
consume = @host_async_func("do:g6-2-owned-record-nested-producer-unknown@0.1.0", "consume-via-stream", (StreamWriter<Outer>) -> Result<nil, ProducerError>)
Ticket = @wasi_resource("do:g6-2-owned-record-nested-producer/source/ticket", { .id i64 })
Inner {
    .ticket Ticket
}
Outer {
    .inner Inner
}
ProducerError error = Io | Pipe | InvalidMode
produce(mode u32) -> Result<nil, ProducerError> { return Ok() }
start() {}
